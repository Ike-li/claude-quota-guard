# Statusline Color Display Issues - Troubleshooting Guide

## Problem

Statusline shows raw color codes (e.g., `#d08770`, `#ebcb8b`) or ANSI escape sequences instead of actual colors.

## Diagnosis

### Step 1: Check Terminal Capability

Run in your Claude Code terminal:
```bash
echo $TERM
echo $COLORTERM
echo -e "\033[91mRED\033[0m \033[92mGREEN\033[0m \033[94mBLUE\033[0m"
```

**Expected**: Colors should display.  
**If broken**: You'll see literal `[91m`, `[92m`, etc.

### Step 2: Verify statusline is running

```bash
jq '.statusLine.command' ~/.claude/settings.json
```

Should show: `bash /path/to/statusline-command.sh`

### Step 3: Test statusline directly

```bash
# Get real Claude Code stdin
echo '{"model":{"display_name":"test"},"context_window":{"used_percentage":50}}' | bash /path/to/statusline-command.sh
```

## Solutions

### Solution 1: Enable COLORTERM (if supported)

Add to your shell profile (`~/.zshrc` or `~/.bashrc`):
```bash
export COLORTERM=truecolor
```

Restart Claude Code.

### Solution 2: Force 16-color mode

Edit `statusline-command.sh`, find the color detection block (around line 46), and **force the 16-color fallback**:

```bash
# Force basic 16 ANSI colors (comment out the if/elif checks)
RED="\033[91m"
PEACH="\033[33m"
YELLOW="\033[93m"
GREEN="\033[92m"
SAPPHIRE="\033[94m"
MAUVE="\033[95m"
SKY="\033[96m"
ROSE="\033[95m"
GOLD="\033[93m"
SUBTEXT="\033[37m"
DIM="\033[90m"
RESET="\033[0m"
```

### Solution 3: Use collect.sh (minimal, no colors)

If colors don't work at all, use the simpler collect.sh:

```bash
# In ~/.claude/settings.json
{
  "statusLine": {
    "type": "command",
    "command": "bash /path/to/hooks/collect.sh"
  }
}
```

This outputs plain text: `ctx 56% · 5h 28% · 7d 8%`

### Solution 4: Check tmux settings (if using tmux)

If inside tmux, add to `~/.tmux.conf`:
```
set -g default-terminal "screen-256color"
set -ga terminal-overrides ",xterm-256color:Tc"
```

Then reload: `tmux source-file ~/.tmux.conf`

## Verification

After applying a solution:

1. Restart Claude Code
2. Check statusline output
3. Colors should render properly

## Known Terminal Compatibility

| Terminal | 24-bit | 256-color | 16-color |
|----------|--------|-----------|----------|
| iTerm2 (macOS) | ✅ | ✅ | ✅ |
| Terminal.app | ❌ | ✅ | ✅ |
| kitty | ✅ | ✅ | ✅ |
| Alacritty | ✅ | ✅ | ✅ |
| tmux (default) | ❌ | ✅ | ✅ |
| tmux (with Tc) | ✅ | ✅ | ✅ |
| VS Code terminal | ✅ | ✅ | ✅ |

## Still Not Working?

If none of the above work, the issue might be:

1. **Claude Code bug**: StatusLine JSON rendering may have issues
2. **Terminal emulator limitation**: Some terminals strip ANSI codes
3. **Shell initialization**: Profile not loading correctly

**Workaround**: Use the CLI dashboard instead:
```bash
/quota-guard watch
```

This runs in a full TUI and should always render colors correctly.

## Reporting Issues

If colors still don't work, collect this info:

```bash
echo "TERM=$TERM"
echo "COLORTERM=$COLORTERM"
echo "SHELL=$SHELL"
uname -a
# Test basic colors
echo -e "\033[91mRED\033[0m"
# Screenshot of statusline output
```

Open an issue at: https://github.com/raylee/claude-quota-guard/issues
