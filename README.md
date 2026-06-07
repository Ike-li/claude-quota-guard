# claude-quota-guard

Stop Claude Code from silently dying at a rate limit — or silently blowing past
its context window — mid-task.

`claude-quota-guard` watches your **5-hour / 7-day rate limits** (subscription)
and your **context-window usage** (every mode), and when either nears its limit
it injects a signal into Claude's context telling it to **converge**: stop
expanding work, write a handoff note, and hand you a paste-ready prompt to resume
in a fresh session.

It works whether you use a Claude.ai **subscription** or an **API key / relay**
(`ANTHROPIC_BASE_URL`) — and it knows the difference.

---

## Why

Claude Code shows your limits in the status line, but the **model itself never
sees them**. So it can cheerfully start a big refactor with 2% of your 5-hour
budget left, then die halfway through — taking your context with it.

This tool closes that gap with three decoupled pieces:

| Piece | Role | Stability |
|---|---|---|
| `collect.sh` (statusLine) | reads the live status JSON, writes a tiny snapshot | data is **live** |
| `.quota-now` snapshot | the bridge between display and model | cheap, unthrottled |
| `guard.sh` (UserPromptSubmit) | reads snapshot, decides tier, injects signal | logic |
| `CLAUDE.md` protocol | tells the model what to do on the signal | rules are **static** |

The key idea: **live data, static policy, decoupled.** Don't hard-code a
number into `CLAUDE.md` (it goes stale); inject the live number via a hook and
keep only the *rules* in `CLAUDE.md`.

---

## Tiers

| Condition | Action | Signal |
|---|---|---|
| ctx ≥ 85% **or** 5h ≥ 85% | **Converge** — write handoff, stop | `[QUOTA-LOW]` |
| 50% ≤ ctx < 85% | **Advise once** — keep working | `[CTX-NOTICE]` |
| below thresholds | silent | — |

The rate-limit tier is **skipped on API/relay mode** (no real 5h/7d concept).
The context tier applies to **both** modes — a full context window hurts either
way. All thresholds are configurable.

| | 5h ≥ 85% | ctx ≥ 85% | ctx 50–85% |
|---|---|---|---|
| **Subscription** | 🔴 converge | 🔴 converge | 🟡 notice |
| **API / relay** | ➖ skipped | 🔴 converge | 🟡 notice |

---

## Install

Requires: `bash`, `awk`, `date`, `stat`, `jq`.

```bash
git clone https://github.com/Ike-li/claude-quota-guard
cd claude-quota-guard
./install.sh
```

The installer:
- checks dependencies
- asks for signal language (`en` / `zh`)
- detects an existing status line and offers to **wrap** it (keep your display)
  or **replace** it
- edits `~/.claude/settings.json` with `jq` (idempotent, backed up)
- appends the convergence protocol to `~/.claude/CLAUDE.md`

Restart Claude Code (or start a new session) to activate.

### Wrap vs standalone

Claude Code allows only **one** statusLine command. If you already have a custom
status line, `claude-quota-guard` runs in **wrap mode**: `collect.sh` extracts
the data, then forwards the original JSON to your status line and prints its
output. Your display is unchanged; data collection happens transparently.

If you have no status line, it installs a minimal one (`ctx N% · 5h N% · 7d N%`).

### Rich status line (the author's own)

This repo also ships **`statusline-command.sh`** — a self-contained two-line bar
(Catppuccin Mocha) showing `ctx · cache% · cache-TTL countdown · 5h/7d (reset +
burn projection) · cost · tokens · git`. It writes the same `.quota-now` snapshot
`guard.sh` reads, so it covers *both* the display and `collect.sh`'s job in one
script. Point your `statusLine` at it for the full bar:

```jsonc
// ~/.claude/settings.json
"statusLine": { "type": "command", "command": "bash ~/.claude/statusline-command.sh", "refreshInterval": 10 }
```

The `cache-TTL countdown` (`⏳4m10s` → `❄cold`) estimates how long the 5-minute
prompt cache stays warm — it resets on each API call and ticks down (floored to
the `refreshInterval`) while idle.

---

## Configure

Edit `config.sh` (created from `config.example.sh` on install). Every value can
also be overridden via environment variable.

```sh
CQG_CTX_NOTICE=50        # ctx% for the advisory notice
CQG_CTX_HALT=85          # ctx% that triggers convergence
CQG_RATE_HALT=85         # 5h% that triggers convergence (subscription)
CQG_LANG=en              # en | zh
CQG_MODE=auto            # auto | subscription | relay
CQG_MAX_AGE=60           # ignore snapshots older than N seconds
CQG_LOG=$HOME/.claude/quota-guard.log   # structured log path; set empty to disable
CQG_LOG_MAX=102400       # rotate log to .log.1 after this many bytes (100 KB)
```

Every invocation appends one line to the log:

```
2026-06-06T05:26:13 sess=abc123 snap=session ctx=80 5h=28 → CTX-NOTICE
2026-06-06T05:26:37 sess=?      snap=missing             → exit
```

Fields: timestamp · `sess` (session ID, `?` when absent) · `snap` (`session` = per-session file, `global` = shared fallback) · `ctx`/`5h` values · decision reached.

---

## Uninstall

```bash
./uninstall.sh
```

Removes the hook, restores or clears the status line (un-wrapping if needed),
strips the `CLAUDE.md` block, and cleans runtime files. `settings.json` is backed
up first.

---

## Test

```bash
./test/test_guard.sh
```

Self-contained regression covering the tier matrix, both modes, notice dedup,
freshness, i18n, and configurable thresholds. Never touches your real
`~/.claude` files.

---

## How it detects subscription vs API/relay

By default (`CQG_MODE=auto`), `guard.sh` checks whether the snapshot contains
real rate-limit data (non-empty 5h field). `collect.sh` writes empty rate fields
on API/relay mode, so this is a reliable, zero-config discriminator. No more
`ANTHROPIC_BASE_URL` leak from your shell environment.

Set `CQG_MODE=subscription` or `CQG_MODE=relay` in `config.sh` to force a
specific mode. The context tier never depends on mode and always runs.

---

## Limitations

- **Turn-boundary only.** The hook fires on `UserPromptSubmit`, so it can't
  interrupt a reply that's already generating. That's fine — convergence means
  "don't expand on the *next* step."
- **Guidance, not a hard stop.** The signal strongly steers the model; it can't
  forcibly halt it. The `CLAUDE.md` protocol uses MUST language to reinforce.
- **Projection is display-only.** The 5h "projected at reset" figure is exposed
  for status lines that want to show it, but it deliberately does **not** trigger
  convergence — early in a window it extrapolates from a tiny sample and
  over-estimates wildly. The only rate trigger is actual `5h ≥ 85%`.
- **API mode has no rate awareness.** Pay-as-you-go has no 5h/7d budget to watch;
  only the context tier applies.

---

## License

MIT
