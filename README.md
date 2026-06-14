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

```bash
# Install
git clone https://github.com/raylee/claude-quota-guard ~/.claude/skills/quota-guard
cd ~/.claude/skills/quota-guard

# Setup (one-time)
/quota-guard setup

# Verify it works
/quota-guard doctor

# Restart Claude Code
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
| 📊 **Live monitoring** | Statusline + TUI dashboard (`/quota-guard watch`) |
| 🎨 **Customizable** | 3 themes, 3 presets, responsive layout |
| 📈 **Analytics** | Cost trends, cache savings, tool stats, error tracking |
| 🌐 **Universal** | Works with subscription OR API relay (auto-detects) |

---

## Usage

### Common Commands

```bash
/quota-guard watch       # Launch live dashboard
/quota-guard config      # Edit settings
/quota-guard theme nord  # Switch theme
/quota-guard doctor      # Diagnose issues
```

Full command reference: [docs/user-guide.md](docs/user-guide.md)

### Configuration

Edit `~/.claude/quota-guard/settings.json`:

```json
{
  "thresholds": {
    "ctxHalt": 85,    // Stop at 85% context
    "rateHalt": 85    // Stop at 85% quota
  },
  "display": {
    "statusline": {
      "preset": "full",          // minimal | compact | full
      "theme": "catppuccin-mocha"
    }
  }
}
```

Or use commands: `/quota-guard preset minimal`, `/quota-guard theme cyberpunk`

Full options: [docs/user-guide.md#configuration](docs/user-guide.md#configuration)

---

## How It Works

```
Claude Code stdin → collect.sh → snapshot file
                                       ↓
User prompt → guard.sh reads snapshot → injects [QUOTA-LOW]
                                              ↓
Model sees signal → writes handoff → stops
```

Architecture details: [docs/architecture.md](docs/architecture.md)

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

- **[Getting Started](docs/getting-started.md)** - 5-minute tutorial
- **[User Guide](docs/user-guide.md)** - Complete reference
- **[Architecture](docs/architecture.md)** - How it works
- **[Troubleshooting](docs/troubleshooting.md)** - Common issues
- **[Contributing](docs/contributing.md)** - Development guide

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

MIT © 2024

---

## Acknowledgments

- [jarrodwatts/claude-hud](https://github.com/jarrodwatts/claude-hud) - Transcript parsing
- [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) - Plugin architecture
- [Catppuccin](https://github.com/catppuccin/catppuccin) - Default theme
