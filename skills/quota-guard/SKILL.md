---
name: quota-guard
description: Monitor quota and context usage, inject convergence signals
version: 1.0.0
author: Ike-li
---

# Quota Guard Skill

Monitor Claude Code's 5h/7d rate limits and context usage. Automatically injects `[QUOTA-LOW]` signals when nearing exhaustion to trigger safe convergence.

## Running commands

When the user invokes `/quota-guard:quota-guard <command> [args]`, run the dispatcher and relay its output:

```bash
bash "${CLAUDE_SKILL_DIR}/quota-guard.sh" <command> [args]
```

## Quick Start

Installed as a plugin (recommended):

```bash
/plugin marketplace add Ike-li/claude-quota-guard
/plugin install quota-guard
/quota-guard:quota-guard setup     # one-time: wire statusLine + build CLI
```

Then restart Claude Code. `/plugin install` auto-wires the guard hook and the
`quota-guard` CLI; `setup` wires the statusLine (which plugins cannot declare on
their own) and marks it as ours so it self-heals across sessions.

**Manual clone (non-plugin):** ensure the dispatcher is executable —
`chmod +x skills/quota-guard/quota-guard.sh` — and run `./install.sh`.

## Commands

Invoke as `/quota-guard:quota-guard <command>`:

| Command | Description |
|---------|-------------|
| `setup` | Wire statusLine, build CLI, mark statusLine owner |
| `config` | **Guided** config — Claude walks you through it (see below) |
| `mode <name>` | Apply a bundle: `full` \| `essential` \| `quiet` |
| `set <path> <val>` | Set one key, e.g. `set features.ctxNotice false` |
| `show` | Print the current effective configuration |
| `watch` | Launch live TUI dashboard |
| `query [--json]` | Show current session state |
| `theme <name>` | Switch color theme |
| `preset <name>` | Switch display preset |
| `doctor` | Diagnose installation |
| `clean` | Clear caches |
| `uninstall` | Remove all components (run BEFORE `/plugin uninstall`) |

## Configuring (guided flow)

When the user runs `/quota-guard:quota-guard config` (or asks to configure / enable /
disable capabilities / choose what to display), drive this flow **in chat**:

1. Run `bash "${CLAUDE_SKILL_DIR}/quota-guard.sh" show` and summarize the current config.
2. Ask (use the option UI) which **mode** they want:
   - **full** (recommended / default) — all data + notices on
   - **essential** — context + quota only, compact statusline
   - **quiet** — convergence only; no `[CTX-NOTICE]`, minimal statusline
   - **custom** — pick individual data + features
3. full / essential / quiet → run `quota-guard.sh mode <name>`.
4. **custom** → ask two multi-selects, then apply each choice with `quota-guard.sh set <path> <value>`:
   - **Display data**: context, quota (5h/7d), git, agents, todos, tokens
   - **Features**: ctx-notice tier, rate monitoring, JSON export, logging
5. Run `show` again to confirm, and tell the user to **restart Claude Code** to apply.

> Guard convergence (the `[QUOTA-LOW]` handoff) is the core capability and is **always
> on** — do not offer it as a toggle. "Just press enter / accept defaults" = `mode full`.

`set` key paths:

| Choice | path | values |
|---|---|---|
| ctx-notice tier | `features.ctxNotice` | `true`/`false` |
| rate monitoring | `mode` | `auto`/`subscription`/`relay` (relay = off) |
| JSON export | `exportJson.enabled` | `true`/`false` |
| logging | `logging.enabled` | `true`/`false` |
| data element | `display.statusline.elements.{context,quota,git,agents,todos,tokens}` | `true`/`false` |
| threshold | `thresholds.{ctxNotice,ctxHalt,rateHalt}` | `0`–`100` |

## Presets

- **minimal** - Quota + context only
- **compact** - Single line, essential info
- **full** - Dual line, all features (default)

## Themes

- **catppuccin-mocha** - Warm pastels (default)
- **cyberpunk** - Neon blue/pink
- **nord** - Cool blues

## How It Works

1. **statusLine hook** (`collect.sh`) - Extracts quota/context from Claude Code's JSON every 10s, writes snapshot
2. **UserPromptSubmit hook** (`guard.sh`) - Reads snapshot, injects `[QUOTA-LOW]` signal when thresholds crossed, **and emits the convergence protocol inline** when it fires
3. **SessionStart hook** (`bridge-statusline.sh`) - Plugins can't declare the primary statusLine, so this re-pins `collect.sh` into `settings.json` each session (self-heals strips / plugin-path changes). Inert until `setup` marks ownership.

## Configuration

**Statusline appearance** — `~/.claude/quota-guard/settings.json` (or the commands below):

```json
{
  "display": {
    "statusline": {
      "preset": "full",
      "theme": "catppuccin-mocha",
      "responsive": true
    }
  }
}
```

```bash
/quota-guard:quota-guard preset minimal
/quota-guard:quota-guard theme nord
```

**Convergence thresholds & feature toggles** live in
`~/.claude/quota-guard/settings.json` and **do drive `guard.sh`/`collect.sh`** (via
`lib/load-config.sh`). Edit via the guided flow, `set`, or directly:

```json
{ "thresholds": { "ctxNotice": 50, "ctxHalt": 85, "rateHalt": 85 },
  "features": { "ctxNotice": true }, "mode": "auto" }
```

Resolution precedence: `CQG_*` env var > `settings.json` > `config.sh` > built-in
default. `config.sh` now only carries the wrapped-statusLine command (wrap mode);
environment variables still override any single value.

## Uninstalling

Run **`/quota-guard:quota-guard uninstall` first** — it restores/clears the
statusLine and clears the owner flag (so the SessionStart bridge goes inert).
**Then** `/plugin uninstall quota-guard`. Doing it the other way leaves a "zombie"
status line that `/plugin uninstall` cannot clear (issue #64074).

## Troubleshooting

Run diagnostics:
```bash
/quota-guard:quota-guard doctor
```

Checks:
- Hook registration (statusLine + UserPromptSubmit)
- CLI functionality
- Snapshot freshness
- Config file validity
- Terminal color support (detects truecolor/256-color/16-color)
- Live color rendering test
- Dependencies (jq, node, npm)

Common issues:
- **Snapshot stale** - Hooks not running, check settings.json
- **No signal injected** - Thresholds too high, lower in config
- **CLI not working** - Run `cd cli && npm install && npm run build`

## Documentation

Full docs: https://github.com/Ike-li/claude-quota-guard
