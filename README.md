# Claude Quota Guard

**Prevent Claude Code from running out of quota mid-task.**

Monitors your 5h/7d rate limits and context usage. When nearing exhaustion, automatically injects a signal that triggers the model to write a handoff and stop gracefully—so you can resume exactly where you left off.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.0.0-green.svg)](CHANGELOG.md)

---

## The Problem

Claude Code shows quota in the statusline, but **the model never sees it**. It can start a big refactor with 2% quota left, then die mid-task—losing your context and progress.

## The Solution

**Quota Guard** closes this gap with three parts:

1. **Monitor**: Tracks quota/context every 10 seconds
2. **Signal**: Injects `[QUOTA-LOW]` into context when threshold crossed
3. **Converge**: Model sees signal, writes handoff, stops cleanly

You get a ready-to-paste resume prompt for the next session.

---

## Quick Start

**Install as a plugin (recommended):**

```bash
/plugin marketplace add raylee/claude-quota-guard
/plugin install quota-guard
/quota-guard:quota-guard setup     # one-time: wire statusLine + build CLI
/quota-guard:quota-guard doctor    # verify
```

Restart Claude Code. `/plugin install` auto-wires the guard hook and the CLI;
`setup` wires the statusLine (which plugins can't declare on their own — see
[How It Works](#how-it-works)) and marks it as ours so it self-heals each session.

**Manual install (non-plugin fallback):**

```bash
git clone https://github.com/raylee/claude-quota-guard
cd claude-quota-guard && ./install.sh
```

**That's it.** Next time you hit 85% quota, you'll see:

```
[QUOTA-LOW] 5h usage at 87%. Converging to handoff...
```

The model will write a handoff file and stop. Copy the resume prompt, paste into a new session, continue.

---

## What You Get

| Feature | Description |
|---------|-------------|
| 🛡️ **Active protection** | Only tool that prevents mid-task exhaustion (others just display) |
| 📊 **Live monitoring** | Statusline + TUI dashboard (`/quota-guard:quota-guard watch`) |
| 🎨 **Customizable** | 3 themes, 3 presets, responsive layout |
| 📈 **Analytics** | Cost trends, cache savings, tool stats, error tracking |
| 🌐 **Universal** | Works with subscription OR API relay (auto-detects) |

---

## Usage

### Common Commands

```bash
/quota-guard:quota-guard config      # Guided setup (modes + custom, in chat)
/quota-guard:quota-guard watch       # Launch live dashboard
/quota-guard:quota-guard theme nord  # Switch theme
/quota-guard:quota-guard doctor      # Diagnose issues
```

Full command reference: [skills/quota-guard/SKILL.md](skills/quota-guard/SKILL.md)

### Configuration

Easiest path — ask in chat: **`/quota-guard:quota-guard config`** walks you through
it (pick a mode, or customize which data shows and which features are on). "Just press
Enter / accept defaults" = everything on.

```bash
/quota-guard:quota-guard config                        # guided: modes + custom
/quota-guard:quota-guard mode essential                # full | essential | quiet
/quota-guard:quota-guard set features.ctxNotice false  # toggle one capability
/quota-guard:quota-guard show                          # current effective config
```

It all lives in **`~/.claude/quota-guard/settings.json`** and now genuinely drives
**both** the guard hooks and the display (resolved by `lib/load-config.sh`):

```json
{ "thresholds": { "ctxHalt": 85, "rateHalt": 85, "ctxNotice": 50 },
  "features": { "ctxNotice": true },
  "display": { "statusline": { "elements": { "context": true, "quota": true, "git": true } } } }
```

Resolution precedence: `CQG_*` env var > `settings.json` > `config.sh` > built-in
default. (`config.sh` is a stable dir, not the ephemeral plugin dir; it now only
carries the wrapped-statusLine command used by wrap mode.)

**Modes:** `full` (all data + notices), `essential` (context + quota, compact),
`quiet` (convergence only — no `[CTX-NOTICE]`, minimal line). Guard convergence is the
core capability and is always on.

---

## How It Works

```
Claude Code stdin → collect.sh (statusLine) → snapshot file
                                                    ↓
User prompt → guard.sh reads snapshot → injects [QUOTA-LOW] + convergence protocol
                                              ↓
Model sees signal → writes handoff → stops
```

**Plugin wiring.** `/plugin install` auto-registers the `guard.sh` (UserPromptSubmit)
hook and the CLI. But Claude Code plugins **cannot declare the primary `statusLine`**
([#64074](https://github.com/anthropics/claude-code/issues/64074)), and `collect.sh`
must run as the statusLine to read the 5h/7d rate-limit JSON. So `setup` wires
`collect.sh` into `settings.json`, and a `SessionStart` hook (`bridge-statusline.sh`)
re-pins it each session — self-healing against settings rewrites and plugin-path
changes. The convergence protocol is emitted **inline by `guard.sh`** when the signal
fires, so nothing is written to your `CLAUDE.md`.

Architecture details: [CLAUDE.md](CLAUDE.md)

---

## Troubleshooting

**Statusline shows raw color codes**  
→ Literal hex (`#d08770`)? Update — older `statusline-command.sh` didn't convert theme colors to ANSI  
→ Literal escapes (`[91m`)? Run `/quota-guard doctor`, check terminal color support  
→ See [docs/troubleshooting.md](docs/troubleshooting.md#-statusline-shows-raw-color-codes)

**Signal not injecting**  
→ Run `/quota-guard doctor`, verify hooks registered  
→ Check thresholds in config (lower if needed)

**CLI not working**  
→ `cd cli && npm install && npm run build`

More: [docs/troubleshooting.md](docs/troubleshooting.md)

---

## Documentation

- **[Getting Started](docs/getting-started.md)** - 5-minute install tutorial
- **[Troubleshooting](docs/troubleshooting.md)** - Common issues
- **[Skill Commands](skills/quota-guard/SKILL.md)** - Full `/quota-guard:quota-guard` reference
- **[Architecture](CLAUDE.md)** - How it works (internals)
- **[Development](docs/DEVELOPMENT.md)** - Contributor guide
- **[Roadmap](docs/ROADMAP.md)** - Planned features

---

## Comparison

| Feature | Quota Guard | claude-hud | oh-my-claudecode |
|---------|-------------|------------|------------------|
| Prevents exhaustion | ✅ Active | ❌ Display only | ❌ Display only |
| Statusline | ✅ | ✅ | ✅ |
| TUI Dashboard | ✅ | ❌ | ✅ |
| Themes | ✅ | ❌ | ✅ |
| Language | Bash+Node | Node | Node |

**Unique value**: Only tool with active intervention—prevents quota exhaustion, not just shows it.

---

## Requirements

- Claude Code 2.1.0+
- Bash 4.0+
- Node.js 16+ (for CLI dashboard)
- jq (for JSON parsing)

Verified on macOS, Linux. Windows via WSL.

---

## License

MIT © 2026

---

## Acknowledgments

- [jarrodwatts/claude-hud](https://github.com/jarrodwatts/claude-hud) - Transcript parsing
- [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) - Plugin architecture
- [Catppuccin](https://github.com/catppuccin/catppuccin) - Default theme
