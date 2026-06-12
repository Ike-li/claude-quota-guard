# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Monitors Claude Code's **5h/7d rate limits** (subscription) and **context-window usage** (all modes). When either nears its limit, injects a signal (`[QUOTA-LOW]` or `[CTX-NOTICE]`) into the model's context so it converges before hitting the limit mid-task.

## Commands

```bash
bash test/test_guard.sh   # Run all tests (self-contained, no side effects)
./install.sh              # Interactive install (wires hooks into ~/.claude/)
./uninstall.sh            # Removes hooks and cleans up
bash -n hooks/guard.sh    # Syntax-check any script without running it
```

## Architecture: live data, static policy, decoupled

Three pieces connected by a one-line tab-separated snapshot file (`~/.claude/.quota-now`):

| Piece | Role | Trigger |
|---|---|---|
| `collect.sh` | Reads Claude Code's status-line JSON from stdin, extracts rate-limit + ctx fields, writes snapshot | Every 10s (statusLine) |
| `.quota-now` | Bridge file — cheap, unthrottled, atomically written via mktemp+mv | — |
| `guard.sh` | Reads snapshot, evaluates tiers, echoes a signal to stdout → injected into context | Every prompt (UserPromptSubmit) |
| `CLAUDE.md` block | Tells the model what to do when it sees the signal | Static rules |

The key idea: numbers go stale if hard-coded into CLAUDE.md, so the **live number** is injected via a hook and only the **rules** live in CLAUDE.md.

### Snapshot format (tab-separated, single line, 6 fields)

```
5h% \t 7d% \t 5h_proj% \t 5h_reset \t 7d_reset \t ctx%
```

Fields absent on API/relay mode are written empty. `guard.sh` parses them with `awk -F'\t'` (robust to empty fields; `read` collapses them).

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
| ctx ≥ CQG_CTX_HALT **or** 5h ≥ CQG_RATE_HALT | `[QUOTA-LOW]` | Converge (handoff + stop) |
| CQG_CTX_NOTICE ≤ ctx < CQG_CTX_HALT | `[CTX-NOTICE]` | Advise once (deduped via stamp file) |
| Below thresholds | silent | — |

Rate-limit tier is gated by `CQG_MODE`: `auto` (detect from snapshot data — 5h field non-empty = subscription), `subscription` (force on), `relay` (force off). Context tier always runs regardless of mode.

### Notification dedup

The `[CTX-NOTICE]` tier fires only **once per crossing**. A stamp file (`~/.claude/.cqg-notice-stamp`) is touched on first notice; subsequent prompts are silent until ctx drops below the notice threshold (which clears the stamp).

### Config (`config.sh`, created from `config.example.sh` on install)

Every value can be overridden via environment variable. Key settings:

- `CQG_CTX_NOTICE` (50), `CQG_CTX_HALT` (85), `CQG_RATE_HALT` (85) — tier thresholds
- `CQG_MODE` (auto) — subscription/relay detection
- `CQG_LANG` (en) — signal language: `en` | `zh`
- `CQG_MAX_AGE` (60) — ignore snapshots older than N seconds
- `CQG_WRAPPED_STATUSLINE` — set by installer in wrap mode; forwards stdin to user's existing status line
- `CQG_EXPORT_JSON` (empty) — opt-in path; when set, `collect.sh` also emits the quota numbers as a standard JSON object (`{updated_at, five_hour, seven_day, context}`, `resets_at` as unix epoch seconds) for external tools to read
- `CQG_SWEEP_RATE` (100), `CQG_SWEEP_MAX_AGE_DAYS` (7) — per-session file sweep: 1-in-N write probability and the age cutoff; `CQG_SWEEP_RATE=0` disables

### Installer modes

Claude Code allows only one statusLine command. If the user already has one, `install.sh` offers **wrap mode**: `collect.sh` extracts data, then forwards stdin to the existing status line — the user's display is unchanged. Otherwise, a minimal standalone line is used (`ctx N% · 5h N% · 7d N%`).

`statusline-command.sh` is a separate rich status line (Catppuccin Mocha, two lines) that can replace `collect.sh` entirely — it writes the same snapshot format so `guard.sh` still works.

### Hook wiring

`install.sh` edits `~/.claude/settings.json` with `jq`:
- `statusLine.command` → `bash …/hooks/collect.sh`
- `hooks.UserPromptSubmit[].hooks[].command` → `bash …/hooks/guard.sh # claude-quota-guard`

The trailing `# claude-quota-guard` comment is a **stable marker** — install/uninstall match it to find the hook regardless of clone path. It's a shell comment, so it doesn't affect execution.

### Test design

`test/test_guard.sh` uses a temp directory (`mktemp -d`, trap cleanup) — never touches real `~/.claude` files. Creates an isolated `config.sh`, writes synthetic snapshots, runs `guard.sh` with controlled env vars, and asserts stdout signals.

### Logging

`guard.sh` appends one structured line per invocation to `CQG_LOG` (default `~/.claude/quota-guard.log`):
```
2026-06-06T05:26:13 sess=abc123 snap=session ctx=80 5h=28 → CTX-NOTICE
```
Log rotates to `.log.1` at `CQG_LOG_MAX` bytes (default 100 KB). Set `CQG_LOG=""` to disable.
