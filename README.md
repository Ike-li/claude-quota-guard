# Claude Quota Guard

**Never run out of quota mid-task again.**

Monitor Claude Code's 5h/7d rate limits and context usage. Automatically injects convergence signals when nearing exhaustion to trigger safe handoff.

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Version](https://img.shields.io/badge/version-1.0.0-green.svg)

---

## Why

Claude Code shows your limits in the status line, but the **model itself never sees them**. So it can cheerfully start a big refactor with 2% of your 5-hour budget left, then die halfway through — taking your context with it.

This tool closes that gap: when quota or context nears exhaustion, it injects a `[QUOTA-LOW]` signal into Claude's context, triggering a convergence protocol that writes a handoff and stops gracefully.

## Features

### 🛡️ Active Protection (Unique!)
- **Signal injection** - Injects `[QUOTA-LOW]` when thresholds crossed
- **Convergence protocol** - Model writes handoff and stops before exhaustion
- **Handoff template** - Resume prompt for seamless continuation

### 📊 Real-time Monitoring
- **Statusline** - Live quota/context display in your terminal
- **TUI dashboard** - `quota-guard watch` for detailed view
- **Responsive layout** - Auto-adjusts to terminal width

### 🎨 Customizable
- **Themes** - catppuccin-mocha, cyberpunk, nord, gruvbox, dracula, tokyo-night
- **Presets** - minimal, compact, full
- **Element toggles** - Show/hide context, quota, git, agents, todos, tokens

### 📈 Advanced Analytics (New!)
- **Trend sparklines** - Visual token/cost progression ▁▂▃▄▅▆▇█
- **Cache savings** - Estimate $ saved via prompt caching
- **Tool stats** - Top 5 tools with error counts
- **Error summary** - Aggregated failure tracking
- **API statistics** - Call count and error rate

## Quick Start

### Install as Skill (Recommended)

```bash
# 1. Clone to your .claude/skills/
git clone https://github.com/raylee/claude-quota-guard ~/.claude/skills/quota-guard

# 2. Install in Claude Code
/quota-guard setup

# 3. Restart Claude Code
```

### Manual Install

```bash
git clone https://github.com/raylee/claude-quota-guard
cd claude-quota-guard
./install.sh
```

## Usage

### Skill Commands

```bash
/quota-guard setup         # Install hooks and build CLI
/quota-guard watch         # Launch live TUI dashboard
/quota-guard query         # Show current session state
/quota-guard config        # Edit settings.json
/quota-guard theme <name>  # Switch color theme
/quota-guard preset <name> # Switch display preset
/quota-guard doctor        # Diagnose installation
/quota-guard clean         # Clear caches
/quota-guard uninstall     # Remove all components
```

### CLI Commands

```bash
quota-guard query          # Text output
quota-guard query --json   # JSON output (for scripts)
quota-guard watch          # Live TUI (Ctrl-C or 'q' to exit)
```

## Configuration

Edit `~/.claude/quota-guard/settings.json`:

```json
{
  "thresholds": {
    "ctxNotice": 50,     // First warning at 50% context
    "ctxHalt": 85,       // Convergence at 85% context
    "rateHalt": 85       // Convergence at 85% quota
  },
  "mode": "auto",        // auto | subscription | relay
  "lang": "en",          // en | zh
  "display": {
    "statusline": {
      "preset": "full",  // minimal | compact | full
      "theme": "catppuccin-mocha",
      "responsive": true,
      "elements": {
        "context": true,
        "quota": true,
        "git": true,
        "agents": true,
        "todos": true,
        "tokens": true
      }
    },
    "tui": {
      "refreshInterval": 1000,
      "showSparklines": true,
      "showErrors": true
    }
  }
}
```

### Quick Config via Commands

```bash
# Switch theme
/quota-guard theme cyberpunk

# Switch preset
/quota-guard preset minimal   # Quota + context only
/quota-guard preset compact   # Single line
/quota-guard preset full      # Dual line (default)

# Edit full config
/quota-guard config
```

## Themes

- **catppuccin-mocha** - Warm pastels (default)
- **cyberpunk** - Neon blue/pink
- **nord** - Cool arctic blues
- **gruvbox** - Retro earth tones *(coming soon)*
- **dracula** - Purple/pink vampiric *(coming soon)*
- **tokyo-night** - Deep blue nights *(coming soon)*

## How It Works

Three components working together:

### 1. Data Collection (`collect.sh`)
- Runs every 10s via `statusLine` hook
- Extracts quota/context from Claude Code's JSON
- Writes snapshot to `~/.claude/.quota-now`

### 2. Signal Injection (`guard.sh`)
- Runs on every prompt via `UserPromptSubmit` hook
- Reads snapshot, evaluates thresholds
- Injects `[QUOTA-LOW]` or `[CTX-NOTICE]` into context

### 3. Convergence Protocol (`CLAUDE.md`)
- Model sees signal and follows protocol:
  1. Judge: has unsaved work OR at clean checkpoint?
  2. If unsaved → write handoff + continuation prompt
  3. If clean → relay status, user decides
- Prevents mid-task quota exhaustion

## Architecture

```
Claude Code stdin JSON
        ↓
   collect.sh (statusLine)
        ↓
   .quota-now snapshot ←────────┐
        ↓                       │
   guard.sh (UserPromptSubmit)  │
        ↓                       │
   [QUOTA-LOW] signal           │
        ↓                       │
   Model sees signal            │
        ↓                       │
   Writes handoff               │
                                │
   CLI reads snapshot ──────────┘
        ↓
   quota-guard watch (TUI)
```

## CLI Dashboard Features

### Token/Cost Stats
- Session totals with per-model breakdown
- API call count and error rate
- Cache savings estimate
- Trend sparklines (5-segment sampling)

### Activity Tracking
- Recent tools (last 20)
- Tool top-5 by call count
- Running agents (live)
- Todo progress
- Error summary (last 10)

### Git Integration
- Branch + dirty count
- Ahead/behind vs upstream (`↑2 ↓1`)
- Stash count (`⚑3`)
- Worktree detection

## Responsive Layout

Statusline automatically adapts to terminal width:

| Width | Mode | Display |
|-------|------|---------|
| < 80 cols | minimal | ctx + quota only |
| 80-120 cols | compact | essential info, single line |
| > 120 cols | full | dual line, all features |

Override with preset:
```bash
/quota-guard preset minimal
```

## Troubleshooting

### Run Diagnostics

```bash
/quota-guard doctor
```

Checks:
- ✓ statusLine hook registered (which script: collect.sh vs statusline-command.sh)
- ✓ UserPromptSubmit hook registered
- ✓ CLI binary built and functional
- ✓ Snapshot fresh (data flowing)
- ✓ Config file valid JSON
- 🎨 Terminal color support (truecolor/256-color/16-color)
- 🎨 Live color rendering test
- 📦 Dependencies (jq, node, npm)

### Common Issues

**Snapshot stale**
```bash
# Check hooks are wired
jq '.statusLine, .hooks.UserPromptSubmit' ~/.claude/settings.json

# Re-run install
/quota-guard setup
```

**No signal injected**
```bash
# Lower thresholds
/quota-guard config
# Set ctxHalt: 75, rateHalt: 75
```

**CLI not working**
```bash
cd cli && npm install && npm run build
```

**Theme not loading**
```bash
# List available themes
/quota-guard theme

# Set theme
/quota-guard theme nord
```

## Development

```bash
# Run tests
bash test/test_guard.sh       # Hook tests
cd cli && npm test             # CLI tests

# Build CLI
cd cli && npm run build

# Syntax check
bash -n hooks/collect.sh
bash -n hooks/guard.sh
bash -n statusline-command.sh
```

## Comparison with Similar Tools

| Feature | quota-guard | claude-hud | oh-my-claudecode | slima4/claude-tui |
|---------|-------------|------------|------------------|-------------------|
| **Signal Injection** | ✅ | ❌ | ❌ | ❌ |
| **Convergence Protocol** | ✅ | ❌ | ❌ | ❌ |
| **Statusline** | ✅ | ✅ | ✅ | ✅ |
| **TUI Dashboard** | ✅ | ❌ | ✅ | ✅ |
| **Themes** | ✅ | ❌ | ✅ | ✅ |
| **Responsive Layout** | ✅ | ❌ | ✅ | ❌ |
| **JSON Config** | ✅ | ✅ | ✅ | ✅ |
| **Language** | Bash+Node | Node | Node | Python |

**Unique Value**: Only tool that **actively prevents** quota exhaustion via signal injection + convergence protocol. Others are display-only.

## Contributing

Pull requests welcome! Please:
1. Run tests before submitting (`bash test/test_guard.sh && cd cli && npm test`)
2. Update docs for new features
3. Follow existing code style (Bash: shellcheck, Node: prettier)

## License

MIT © raylee

## Acknowledgments

- Inspired by [jarrodwatts/claude-hud](https://github.com/jarrodwatts/claude-hud) (transcript parsing)
- [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) (plugin architecture)
- [Catppuccin](https://github.com/catppuccin/catppuccin) (color scheme)
- [slima4/claude-tui](https://github.com/slima4/claudeui) (sparkline inspiration)
