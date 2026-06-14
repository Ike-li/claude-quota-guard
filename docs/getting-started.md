# Getting Started

Complete this guide in **5 minutes** to get Claude Quota Guard running.

---

## Prerequisites

Before installing, verify you have:

```bash
# Check Claude Code version
claude --version  # Need 2.1.0+

# Check dependencies
which bash jq node npm
```

**Missing dependencies?**
- macOS: `brew install jq node`
- Ubuntu/Debian: `sudo apt install jq nodejs npm`
- Arch: `sudo pacman -S jq nodejs npm`

---

## Step 1: Install

```bash
# Clone to Claude Code's skills directory
git clone https://github.com/raylee/claude-quota-guard ~/.claude/skills/quota-guard

# Navigate to directory
cd ~/.claude/skills/quota-guard
```

**Why `.claude/skills/`?**  
Claude Code loads skills from this directory automatically. You can use `/quota-guard` commands without additional setup.

---

## Step 2: Setup

```bash
# In Claude Code, run:
/quota-guard setup
```

This will:
1. ✅ Register hooks in `~/.claude/settings.json`
2. ✅ Build CLI dashboard (`cli/dist/`)
3. ✅ Create default config (`~/.claude/quota-guard/settings.json`)
4. ✅ Ask for language preference (en/zh)

**Expected output:**
```
→ Checking dependencies...
  ✓ all present
→ Installed settings.json
Signal language? [en/zh] (default en): en
→ Wiring hooks...
  ✓ statusLine hook
  ✓ UserPromptSubmit hook
→ Building CLI...
  ✓ Compiled successfully
✅ Installation complete! Restart Claude Code.
```

---

## Step 3: Verify

After restarting Claude Code:

```bash
/quota-guard doctor
```

**Look for these checks:**
```
✓ statusLine hook registered
  └─ Using: statusline-command.sh (rich display)
✓ UserPromptSubmit hook registered
✓ CLI binary found
  └─ CLI functional
✓ Snapshot fresh (Xs old)
✓ Config file found
  └─ JSON valid
🎨 Terminal Capability:
  └─ ✓ 24-bit truecolor supported
✅ Installation looks healthy!
```

**If you see ❌ or ⚠️**: Jump to [Troubleshooting](#troubleshooting) below.

---

## Step 4: Test It

### See the statusline

Look at the bottom of your Claude Code terminal. You should see:

```
📁 quota-guard  main  Opus 4.8  ctx 45% 💚  5h 12% ↻2h  🕐 14:23
💰 $0.23  ⏱ 5m32s  +847/-123  🪟 450k/1M
```

**Elements:**
- 📁 Project + git branch
- Model name
- Context usage (color-coded)
- 5h/7d quota (with reset time)
- Cost, duration, line changes
- Token window usage

### Trigger a signal (optional)

To see the convergence protocol in action, temporarily lower the halt threshold in
`config.sh` (in the install directory) — `guard.sh` reads it:

```bash
# config.sh
CQG_CTX_HALT=50      # was 85

# Now use Claude Code normally. When context reaches 50%, you'll see:
# [QUOTA-LOW] Context at 52%. Converging...
```

The model will:
1. Stop expanding work
2. Write `~/.claude/projects/.../memory/handoff-<timestamp>.md`
3. Output a ready-to-paste resume prompt

**Restore it:** set `CQG_CTX_HALT=85` again (or remove the override).

---

## Step 5: Explore

### Try the dashboard

```bash
/quota-guard watch
```

Live TUI showing:
- Token/cost trends (sparklines)
- Tool usage stats
- Running agents
- Todo progress
- Error summary

Press `q` or Ctrl-C to exit.

### Try themes

```bash
/quota-guard theme      # List available
/quota-guard theme nord # Switch to Nord theme
# Restart Claude Code to see changes
```

Available: `catppuccin-mocha` (default), `cyberpunk`, `nord`

### Try presets

```bash
/quota-guard preset minimal   # Quota + context only
/quota-guard preset compact   # Single line
/quota-guard preset full      # Dual line (default)
# Restart Claude Code to see changes
```

---

## Troubleshooting

### ❌ statusLine hook not found

**Symptom**: Doctor says "statusLine hook not found"

**Fix**:
```bash
/quota-guard setup  # Re-run setup
# Or manually edit ~/.claude/settings.json:
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/skills/quota-guard/statusline-command.sh"
  }
}
```

### ❌ CLI not built

**Symptom**: Doctor says "CLI not built"

**Fix**:
```bash
cd ~/.claude/skills/quota-guard/cli
npm install
npm run build
```

### ⚠️ Snapshot stale

**Symptom**: Doctor says "Snapshot stale (>60s old)"

**Meaning**: statusLine hook isn't running. Likely hooks not registered.

**Fix**:
```bash
/quota-guard setup
# Restart Claude Code
```

### 🎨 Colors broken

**Symptom**: Statusline shows `[91m●[0m` instead of colored circles

**Meaning**: Terminal doesn't support ANSI colors.

**Fix**: See [Troubleshooting](troubleshooting.md)

---

## Next Steps

- [Skill Commands](../skill/SKILL.md) - All `/quota-guard` commands
- [Troubleshooting](troubleshooting.md) - Solutions to common issues
- [Architecture](../CLAUDE.md) - How it works (internals)
- [Development](DEVELOPMENT.md) - Contributor setup and guidelines

---

## Quick Reference

```bash
# Common commands
/quota-guard watch       # Live dashboard
/quota-guard config      # Edit settings
/quota-guard theme <name>   # Switch theme
/quota-guard preset <name>  # Switch preset
/quota-guard doctor      # Diagnose issues
/quota-guard clean       # Clear caches
/quota-guard help        # Show all commands

# Config location
~/.claude/quota-guard/settings.json

# Log location
~/.claude/quota-guard.log
```

**Got stuck?** Open an issue: https://github.com/raylee/claude-quota-guard/issues
