---
name: quota-guard
description: Monitor quota and context usage, inject convergence signals
version: 1.0.0
author: raylee
---

# Quota Guard Skill

Monitor Claude Code's 5h/7d rate limits and context usage. Automatically injects `[QUOTA-LOW]` signals when nearing exhaustion to trigger safe convergence.

## Quick Start

```bash
/quota-guard setup      # Install hooks and build CLI
/quota-guard watch      # Launch live dashboard
```

**Note**: If you cloned manually (not via plugin), ensure the skill script is executable:
```bash
chmod +x ~/.claude/skills/quota-guard/skill/quota-guard.sh
```

## Commands

| Command | Description |
|---------|-------------|
| `setup` | Install hooks and build CLI |
| `watch` | Launch live TUI dashboard |
| `query [--json]` | Show current session state |
| `config` | Edit settings.json |
| `theme <name>` | Switch color theme |
| `preset <name>` | Switch display preset |
| `doctor` | Diagnose installation |
| `clean` | Clear caches |
| `uninstall` | Remove all components |

## Presets

- **minimal** - Quota + context only
- **compact** - Single line, essential info
- **full** - Dual line, all features (default)

## Themes

- **catppuccin-mocha** - Warm pastels (default)
- **cyberpunk** - Neon blue/pink
- **nord** - Cool blues
- **gruvbox** - Retro earth tones
- **dracula** - Purple/pink
- **tokyo-night** - Deep blues

## How It Works

1. **statusLine hook** (`collect.sh`) - Extracts quota/context from Claude Code's JSON every 10s, writes snapshot
2. **UserPromptSubmit hook** (`guard.sh`) - Reads snapshot, injects `[QUOTA-LOW]` signal when thresholds crossed
3. **CLAUDE.md** - Model sees signal and follows convergence protocol (write handoff + stop)

## Configuration

Edit `~/.claude/quota-guard/settings.json`:

```json
{
  "thresholds": {
    "ctxNotice": 50,
    "ctxHalt": 85,
    "rateHalt": 85
  },
  "display": {
    "statusline": {
      "preset": "full",
      "theme": "catppuccin-mocha",
      "responsive": true
    }
  }
}
```

Or use commands:
```bash
/quota-guard preset minimal
/quota-guard theme nord
```

## Troubleshooting

Run diagnostics:
```bash
/quota-guard doctor
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

Full docs: https://github.com/raylee/claude-quota-guard
