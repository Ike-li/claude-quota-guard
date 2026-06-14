# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Monitors Claude Code's **5h/7d rate limits** (subscription) and **context-window usage** (all modes). When either nears its limit, injects a signal (`[QUOTA-LOW]` or `[CTX-NOTICE]`) into the model's context so it converges before hitting the limit mid-task.

## Commands

```bash
bash test/test_guard.sh        # guard.sh tiers/modes/snapshot tests (self-contained)
bash test/test_statusline.sh   # statusline color rendering + depth downgrade (self-contained)
./install.sh              # Interactive install (wires hooks into ~/.claude/)
./uninstall.sh            # Removes hooks and cleans up
bash -n hooks/guard.sh    # Syntax-check any script without running it

(cd cli && npm install && npm run build)   # one-time: build the dashboard CLI
(cd cli && npm test)                       # cli tests (builds first, node --test)
./bin/quota-guard query [--json]           # one-shot session state (external interface)
./bin/quota-guard watch                    # live TUI dashboard
```

## Architecture: live data, static policy, decoupled

Three pieces connected by a one-line tab-separated snapshot file (`~/.claude/.quota-now`):

| Piece | Role | Trigger |
|---|---|---|
| `collect.sh` | Reads Claude Code's status-line JSON from stdin, extracts rate-limit + ctx fields + activity (via `quota-guard _activity`), writes snapshot | Every 10s (statusLine) |
| `.quota-now` | Bridge file — cheap, unthrottled, atomically written via mktemp+mv | — |
| `guard.sh` | Reads snapshot, evaluates tiers, echoes a signal to stdout → injected into context. On the CONVERGE tier it **also emits the convergence protocol inline** (from `templates/convergence.*.md`) | Every prompt (UserPromptSubmit) |

The key idea: numbers go stale if hard-coded, so the **live number** is injected via a hook. The **convergence rules** are emitted inline by `guard.sh` only when `[QUOTA-LOW]` fires (rare), so the tool is self-contained and writes nothing to your `CLAUDE.md`. (`install.sh` no longer appends the protocol; older installs that did still work, and `uninstall.sh` still strips that block.)

### Snapshot format (tab-separated, single line, 8 fields)

```
5h% \t 7d% \t 5h_proj% \t 5h_reset \t 7d_reset \t ctx% \t agents_running \t todos_pending
```

Fields absent on API/relay mode are written empty. `guard.sh` parses them with `awk -F'\t'` (robust to empty fields; `read` collapses them).

**agents_running / todos_pending**: extracted by `collect.sh` via `quota-guard _activity` (reads transcript JSONL). Used by guard.sh to distinguish "unsaved work" (converge immediately) from "clean checkpoint" (relay status, user decides).

**ctx fallback:** `collect.sh` prefers Claude Code's native `context_window.used_percentage`, but treats absent **or `0`** as "not yet populated" (fresh session / first frame after a compact, when `current_usage` already holds real initial-context tokens). In that case it recomputes ctx from `current_usage` tokens ÷ `context_window_size` so the snapshot isn't under-reported. Mirrors claude-hud's `getContextPercent`.

**Suspicious-zero guard:** if ctx is 0/absent **and** every `current_usage` counter is zero **and** a real `context_window` block exists (`context_window_size > 0`), the frame is a Claude Code reporting glitch (a live session always holds system-prompt tokens), not an empty context. `collect.sh` **skips the snapshot/export write** so the previous frame survives and ages out via `CQG_MAX_AGE` (fail-safe) — rather than clobbering good data with `ctx=0` and misleading guard into "context empty". The `size > 0` gate means rate-only / no-context-window frames are never suppressed; a genuinely fresh session has no prior snapshot to protect, so skipping is correct there too. Mirrors claude-hud's `isSuspiciousZero`.

### Per-session snapshots

When a `session_id` is available, `collect.sh` also writes `${CQG_SNAPSHOT}-${session_id}`. `guard.sh` reads **only** that per-session file — never the shared global `.quota-now` — because every session writes global (`cqg_write_snapshot` writes both), so reading global lets one session inherit another's numbers (e.g. a relay session with no rate data of its own picking up a subscription session's `5h=98%`). If the per-session file doesn't exist yet (collect.sh hasn't run with this id — e.g. SDK child sessions), guard exits silent rather than cross-talk. The global file is consulted **only when there is no session_id at all**.

### Shared library (`lib/snapshot.sh`)

Sourced by `collect.sh`, `guard.sh`, and `statusline-command.sh`. Provides:

- `cqg_write_snapshot` — atomic write (mktemp + mv) of both global and per-session files
- `cqg_write_export_json` — opt-in JSON export (mktemp + mv, mode 0600) for *other* tools to consume; no-op unless `CQG_EXPORT_JSON` is set; requires jq; empty fields serialize as JSON `null`
- `cqg_sweep_stale` — amortized cleanup of abandoned per-session files; fires on ~1-in-`CQG_SWEEP_RATE` writes (default 100), deletes `${base}-*` files older than `CQG_SWEEP_MAX_AGE_DAYS` (default 7). Global/temp files never match the `<base>-*` glob; active sessions are protected by freshness
- `cqg_stat_mtime` / `cqg_stat_size` — portable stat (BSD/macOS vs Linux), platform cached
- `cqg_sanitize_session_id` — strips unsafe chars from session IDs for filename use
- `cqg_five_hour_projection` — burn-rate projection (current pace → where we'll be at window reset)
- `cqg_fmt_reset_delta` — epoch → human-readable label (`3d`, `4h`, `12m`, `45s`, `now`)
- `CQG_FIVE_HOUR_WINDOW` — central constant (18000 seconds); change here only if Anthropic changes the window

### Tiers (evaluated in `guard.sh`)

| Condition | Signal | Action |
|---|---|---|
| ctx ≥ CQG_CTX_HALT **or** 5h ≥ CQG_RATE_HALT | `[QUOTA-LOW]` | **If** agents_running > 0 **or** todos_pending > 0: converge (handoff + stop). **Else**: relay status, user decides. |
| CQG_CTX_NOTICE ≤ ctx < CQG_CTX_HALT **and** `features.ctxNotice` on | `[CTX-NOTICE]` | Advise once (deduped via stamp file). Silent when `features.ctxNotice=false` |
| Below thresholds | silent | — |

Rate-limit tier is gated by `CQG_MODE`: `auto` (detect from snapshot data — 5h field non-empty = subscription), `subscription` (force on), `relay` (force off). Context tier always runs regardless of mode.

### Notification dedup

The `[CTX-NOTICE]` tier fires only **once per crossing**. A stamp file (`~/.claude/.cqg-notice-stamp`) is touched on first notice; subsequent prompts are silent until ctx drops below the notice threshold (which clears the stamp).

### Config (`settings.json` authoritative; resolved by `lib/load-config.sh`)

`lib/load-config.sh` is the **single config resolver**, sourced by `guard.sh`, `collect.sh`, and `statusline-command.sh`. It resolves everything into `CQG_*` env vars with this precedence:

**`$CQG_CONFIG` (explicit legacy/isolated file — tests & power users; skips JSON) > individual `CQG_*` env > `~/.claude/quota-guard/settings.json` > `config.sh` baseline (stable dir) > built-in default.**

`settings.json` (schema in `config/settings.schema.json`) is authoritative and now **genuinely drives the guard**, not just the statusline — this resolves the former *config-split* where `guard.sh`/`collect.sh` ignored JSON. `config.sh` survives only to carry `CQG_WRAPPED_STATUSLINE` (wrap mode) and as a legacy fallback. The plugin install dir is ephemeral, so neither file lives there.

> jq gotcha: `json_get` must **not** use jq's `//` operator — `false // x` evaluates to `x`, which would silently flip every boolean toggle to its default. It uses an explicit null/empty check instead. (`mode`/`set`/`show` in the skill and the `show` command had the same trap.)

Key settings (JSON path → `CQG_*`):
- `thresholds.{ctxNotice,ctxHalt,rateHalt}` (50/85/85) — tier thresholds
- `features.ctxNotice` (true) → `CQG_FEATURE_CTX_NOTICE` — gates the `[CTX-NOTICE]` tier (guard convergence is always on, never a toggle)
- `mode` (auto) → `CQG_MODE` — subscription/relay detection (relay = rate monitoring off)
- `lang` (en) → `CQG_LANG`
- `display.statusline.elements.*` → `CQG_SHOW_*` — which data shows (`collect.sh` honors context/quota; `statusline-command.sh` honors all six)
- `display.statusline.{preset,theme,responsive}`; `display.tui.{refreshInterval,showSparklines}` (read by the CLI via `cli/src/config.ts`)
- `snapshot.{maxAge,sweepRate,sweepMaxAgeDays}`, `logging.{enabled,maxSize,path}`, `exportJson.{enabled,path}`

**Config flow (model-driven):** the `quota-guard` skill drives configuration in chat — on `/quota-guard:quota-guard config`, Claude reads current state (`quota-guard.sh show`), asks for a mode (`full`/`essential`/`quiet`/`custom`) via the option UI, and applies it with `quota-guard.sh mode <name>` or `set <dotpath> <value>` (jq writes; dotpath sanitized against injection, values type-coerced). `install.sh` prompts for a mode on a **fresh** config (TTY only), defaulting `full`; it never clobbers an existing config.

### Installer modes

Claude Code allows only one statusLine command. If the user already has one, `install.sh` offers **wrap mode**: `collect.sh` extracts data, then forwards stdin to the existing status line — the user's display is unchanged. Otherwise, a minimal standalone line is used (`ctx N% · 5h N% · 7d N%`).

`statusline-command.sh` is a separate rich status line (Catppuccin Mocha, two lines) that can replace `collect.sh` entirely — it writes the same snapshot format so `guard.sh` still works.

### Dashboard CLI (`cli/` — Node/TS)

The bash hooks feed the **model** (converge signal); `cli/` feeds **humans and external apps**. It reads the transcript JSONL directly, so it works in `claude -p` / SDK headless mode where the statusLine never fires and the snapshot pipeline is blind.

| Module | Role |
|---|---|
| `cli/src/transcript.ts` | Streaming JSONL parser (adapted from claude-hud): tools, agents (background completion via queue-operation timestamps), todos, skills, MCP servers, cumulative tokens (dual-logging dedup) — both a flat total and a per-model split keyed on each turn's `message.model`, for per-model costing — session metadata. In-memory cache keyed by (path, mtime, size) keeps the watch loop cheap. |
| `cli/src/snapshot.ts` | Reads the bash side's `.quota-now` for 5h/7d/ctx. **Per-session strict, mirroring guard.sh**: a known session id reads only its own file, never global (cross-talk); global only when no session id is known. |
| `cli/src/aggregate.ts` + `types.ts` | Merge into one `HudState` consumed by both surfaces. `schemaVersion` stamped for external consumers — contract in `cli/SCHEMA.md`. |
| `cli/src/query.ts` / `tui.ts` | `query [--json]` one-shot output for `claude -p`/SDK apps; `watch` zero-dependency ANSI TUI (alt-screen, Catppuccin), clean teardown on q/Ctrl-C/SIGTERM. |
| `cli/src/format.ts` | Shared formatting + token-derived cost estimate (per-MTok pricing table; unknown models → `null`, never a silent wrong guess). `estimateCostByModel` prices each model's bucket at its own rate and sums them, so mixed-model sessions aren't charged at one blanket rate — the total stays `null` if any token-bearing bucket is unpriceable. |
| `bin/quota-guard` | Thin bash launcher exec'ing `cli/dist/cli.js`. |

**Data boundary:** transcript carries activity + context tokens in all modes; subscription 5h/7d% lives **only** in the snapshot. Pure headless with no per-session snapshot → `quota: none` (honest), activity/context still work. Context % from snapshot keeps `windowSize` null (real window may be 1M); transcript-derived % assumes `--window` (default 200k).

Tests: `cli/test/aggregate.test.js` (node built-in runner) drives the compiled `dist/` against fixture transcripts (single- and mixed-model); pricing table and per-model cost split locked by exact-rate assertions.

### Hook wiring

`install.sh` edits `~/.claude/settings.json` with `jq`:
- `statusLine.command` → `bash …/hooks/collect.sh`
- `hooks.UserPromptSubmit[].hooks[].command` → `bash …/hooks/guard.sh # claude-quota-guard`

The trailing `# claude-quota-guard` comment is a **stable marker** — install/uninstall match it to find the hook regardless of clone path. It's a shell comment, so it doesn't affect execution.

### Plugin distribution

The repo doubles as a Claude Code **plugin** (primary distribution): `.claude-plugin/plugin.json` (manifest), `.claude-plugin/marketplace.json` (so `/plugin marketplace add Ike-li/claude-quota-guard` → `/plugin install quota-guard` works), `hooks/hooks.json`, and the skill at `skills/quota-guard/`.

What auto-wires vs. what needs `setup`:

- **Auto on `/plugin install`** (via `hooks/hooks.json`, using `${CLAUDE_PLUGIN_ROOT}` which expands in hook context): the `guard.sh` UserPromptSubmit hook and the `bridge-statusline.sh` SessionStart hook. The `bin/quota-guard` CLI is auto-added to PATH.
- **Needs `/quota-guard:quota-guard setup` once**: the **statusLine**. Plugins **cannot declare the primary `statusLine`** in the manifest (only `agent`/`subagentStatusLine` — Claude Code issue #64074), and `${CLAUDE_PLUGIN_ROOT}` is **not** expanded in the statusLine subprocess (#52079). But `collect.sh` must run as the statusLine to read the 5h/7d rate-limit JSON (#27508), which lives nowhere else. So `setup` (`install.sh`) wires `collect.sh` into `settings.json` imperatively and writes an **owner flag** (`~/.claude/quota-guard/.statusline-owner`).

**`bridge-statusline.sh` (SessionStart):** gated on the owner flag (inert until `setup` runs — `/plugin install` alone never touches the statusLine). When enabled, it re-pins `collect.sh` into `settings.json` using the hook-context-expanded `${CLAUDE_PLUGIN_ROOT}` (baked as an absolute path, since the statusLine context can't expand it). This self-heals two failure modes: settings partial-rewrite stripping the field (#62486), and the plugin path changing on update. It never clobbers a foreign statusLine (only manages `collect.sh`; wrap is handled by `collect.sh`'s own `CQG_WRAPPED_STATUSLINE`).

**Uninstall ordering:** `/plugin uninstall` does **not** reverse the imperative statusLine write (zombie status line, #64074). So run `/quota-guard:quota-guard uninstall` (→ `uninstall.sh`) **first** — it restores/clears the statusLine and removes the owner flag (bridge goes inert) — **then** `/plugin uninstall`.

**`install.sh` is the non-plugin fallback** — same wiring via `jq` into `~/.claude/settings.json`, for users who don't use marketplaces.

### Test design

Both `test/test_guard.sh` and `test/test_statusline.sh` use a temp directory (`mktemp -d`, trap cleanup) — never touching real `~/.claude` files. `test_guard.sh` creates an isolated `config.sh`, writes synthetic snapshots, runs `guard.sh` with controlled env vars, and asserts stdout signals. `test_statusline.sh` renders `statusline-command.sh` under an isolated `CLAUDE_CONFIG_DIR` (per-theme `settings.json`) and asserts theme `#RRGGBB` hex is converted to ANSI — never printed raw — across truecolor/256/16 depths, and that an empty `mode_parts` array doesn't blank the line.

### Logging

`guard.sh` appends one structured line per invocation to `CQG_LOG` (default `~/.claude/quota-guard.log`):
```
2026-06-06T05:26:13 sess=abc123 snap=session ctx=80 5h=28 → CTX-NOTICE
```
Log rotates to `.log.1` at `CQG_LOG_MAX` bytes (default 100 KB). Set `CQG_LOG=""` to disable.
