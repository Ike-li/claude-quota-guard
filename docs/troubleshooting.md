# Troubleshooting

Solutions to common issues with Claude Quota Guard.

---

## Quick Diagnosis

**Always start here:**

```bash
/quota-guard doctor
```

This runs a series of checks and usually identifies the problem. Look for ❌ or ⚠️ symbols.

---

## Installation Issues

### ❌ settings.json not found

**Symptom**: `doctor` says "settings.json not found"

**Cause**: Claude Code not initialized in this directory.

**Fix**:
```bash
# Run Claude Code at least once
claude

# Then retry setup
/quota-guard setup
```

---

### ❌ statusLine hook not found

**Symptom**: Doctor output shows:
```
❌ statusLine hook not found
   Run: /quota-guard setup
```

**Cause**: Hooks not registered during installation.

**Fix**:
```bash
# Automatic
/quota-guard setup

# Or manual (if setup fails)
# Edit ~/.claude/settings.json:
{
  "statusLine": {
    "type": "command",
    "command": "bash /path/to/quota-guard/statusline-command.sh",
    "refreshInterval": 10
  }
}
```

**Verify**:
```bash
jq '.statusLine' ~/.claude/settings.json
# Should show the command path
```

---

### ❌ UserPromptSubmit hook not found

**Symptom**: Signal never injects, model doesn't see `[QUOTA-LOW]`

**Cause**: guard.sh hook not registered.

**Fix**:
```bash
# Automatic
/quota-guard setup

# Or manual
# Edit ~/.claude/settings.json:
{
  "hooks": {
    "UserPromptSubmit": [{
      "matcher": ".*",
      "hooks": [{
        "type": "command",
        "command": "bash /path/to/quota-guard/hooks/guard.sh"
      }]
    }]
  }
}
```

**Verify**:
```bash
jq '.hooks.UserPromptSubmit' ~/.claude/settings.json
# Should show the guard.sh command
```

---

### ⚠️ CLI not built

**Symptom**: 
```
⚠️  CLI not built
   Run: cd cli && npm install && npm run build
```

**Cause**: TypeScript CLI not compiled.

**Impact**: `/quota-guard watch` won't work (but statusline/hooks work fine).

**Fix**:
```bash
cd ~/.claude/skills/quota-guard/cli
npm install
npm run build

# Verify
ls dist/cli.js  # Should exist
```

---

### ⚠️ Snapshot stale

**Symptom**: `doctor` shows "Snapshot stale (>60s old)"

**Cause**: statusLine hook not running (hooks not registered OR Claude Code not restarted).

**Fix**:
```bash
# 1. Verify hook is registered
jq '.statusLine.command' ~/.claude/settings.json

# 2. Restart Claude Code

# 3. Wait 10s, check again
/quota-guard doctor
# Should show "Snapshot fresh"
```

**If still stale**:
```bash
# Check if collect.sh can run manually
echo '{"context_window":{"used_percentage":50}}' | \
  bash ~/.claude/skills/quota-guard/hooks/collect.sh

# Should output: ctx 50%
```

---

## Display Issues

### 🎨 Statusline shows raw color codes

This has **two distinct forms** with different causes — check which you see.

#### Form A — literal hex (`#d08770`, `#5e81ac`, `#b48ead`)

**Cause**: A theme's `#RRGGBB` colors weren't translated to ANSI escapes. Themes
(`themes/*.sh`) define colors as hex; `statusline-command.sh` converts them. Older
versions didn't, so the raw hex printed. **This is a code bug, not a terminal
issue** — changing `$COLORTERM`/`$TERM` will *not* help.

**Fix**: Update `statusline-command.sh` to a version that converts theme hex to
ANSI (it now does this automatically, degrading truecolor → 256 → 16 by terminal
capability). If `~/.claude` symlinks the repo, `git pull` suffices. Confirm:
```bash
grep -q hex_to_ansi statusline-command.sh && echo "✓ fixed" || echo "✗ outdated"
```

#### Form B — literal escapes (`[91m●[0m`)

**Cause**: Your terminal isn't interpreting ANSI escape sequences at all.

**Diagnosis**:
```bash
# Check terminal capability
echo $TERM
echo $COLORTERM

# Test color rendering
echo -e "\033[91mRED\033[0m"
# Should show red text, not literal [91m
```

**Fix 1: Enable truecolor**
```bash
# Add to ~/.zshrc or ~/.bashrc
export COLORTERM=truecolor

# Restart terminal
source ~/.zshrc
```

**Fix 2: Try 256-color mode**
```bash
export TERM=xterm-256color
```

**Fix 3: Force 16-color** (Form B only — the status line auto-degrades by
terminal capability, so no code edit is needed):
```bash
export COLORTERM= TERM=xterm
```

**Fix 4: Use minimal statusline**

Edit `~/.claude/settings.json`:
```json
{
  "statusLine": {
    "command": "bash /path/to/hooks/collect.sh"
  }
}
```

This uses plain text: `ctx 56% · 5h 28% · 7d 8%`

**Fix 5 (tmux users): Enable truecolor in tmux**

Add to `~/.tmux.conf`:
```
set -g default-terminal "screen-256color"
set -ga terminal-overrides ",xterm-256color:Tc"
```

Reload: `tmux source-file ~/.tmux.conf`

---

### 🎨 Emoji not displaying

**Symptom**: See `?` or `□` instead of 📁 🤖 💰

**Cause**: Terminal font doesn't support emoji.

**Fix**:
1. Install a font with emoji support:
   - macOS: Use default Terminal.app or iTerm2
   - Linux: Install `fonts-noto-color-emoji`
   - Windows: Use Windows Terminal

2. Or disable emoji (edit `statusline-command.sh`, replace emoji with ASCII):
   ```bash
   # Before: 📁 project
   # After:  [project]
   ```

---

### ⚠️ Statusline not updating

**Symptom**: Numbers frozen, don't change during session

**Cause**: `refreshInterval` too high OR snapshot not being written.

**Fix**:
```bash
# Check refresh interval
jq '.statusLine.refreshInterval' ~/.claude/settings.json
# Should be 10 (seconds)

# Check if snapshot is being written
watch -n 1 'ls -lh ~/.claude/.quota-now*'
# Should see timestamps updating
```

---

## Signal Injection Issues

### ⚠️ Signal never appears

**Symptom**: Context/quota exceeds threshold, but no `[QUOTA-LOW]` in conversation

**Diagnosis**:
```bash
# 1. Check UserPromptSubmit hook
jq '.hooks.UserPromptSubmit' ~/.claude/settings.json

# 2. Check guard.sh can run
bash ~/.claude/skills/quota-guard/hooks/guard.sh
# Should output nothing (or a signal if threshold crossed)

# 3. Check thresholds (guard.sh reads config.sh, NOT settings.json)
grep -E 'CQG_(CTX|RATE)' ~/.claude/skills/quota-guard/config.sh
```

**Fix 1: Lower thresholds**

Edit `config.sh` in the install directory — `guard.sh` reads it, not `settings.json`:
```bash
CQG_CTX_HALT=75      # lower from 85
CQG_RATE_HALT=75
```

**Fix 2: Check log**
```bash
tail -20 ~/.claude/quota-guard.log
# Look for guard.sh invocations
```

**Fix 3: Test manually**
```bash
# Create fake snapshot at 90%
echo -e "90\t90\t0\t0\t0\t90\t0\t0" > ~/.claude/.quota-now

# Run guard
bash hooks/guard.sh
# Should output: [QUOTA-LOW] signal
```

---

### ⚠️ Model ignores signal

**Symptom**: `[QUOTA-LOW]` appears but model continues without handoff

**Cause**: CLAUDE.md convergence protocol not loaded OR model confused.

**Fix 1: Verify CLAUDE.md**
```bash
# Check if protocol exists
grep -i "QUOTA-LOW" ~/.claude/CLAUDE.md

# Should contain convergence instructions
```

**Fix 2: Re-install**
```bash
/quota-guard setup
# This appends protocol to CLAUDE.md if missing
```

**Fix 3: Explicit instruction**

When signal appears, tell the model directly:
```
You just received a [QUOTA-LOW] signal. Please follow the convergence protocol:
write a handoff file and provide a resume prompt.
```

---

## Configuration Issues

### ❌ Config file syntax error

**Symptom**: `doctor` shows "JSON syntax error"

**Cause**: Invalid JSON in `~/.claude/quota-guard/settings.json`

**Fix**:
```bash
# Validate JSON
jq empty ~/.claude/quota-guard/settings.json
# Shows line number of error

# Or restore default
cp ~/.claude/skills/quota-guard/config/settings.default.json \
   ~/.claude/quota-guard/settings.json
```

---

### ⚠️ Theme not loading

**Symptom**: Run `/quota-guard theme nord` but colors don't change

**Cause**: 
1. Theme file missing
2. Claude Code not restarted
3. Terminal can't render colors

**Fix**:
```bash
# 1. Verify theme exists
ls ~/.claude/skills/quota-guard/themes/nord.sh

# 2. Check config
jq '.display.statusline.theme' ~/.claude/quota-guard/settings.json
# Should show "nord"

# 3. Restart Claude Code (required!)

# 4. Test terminal colors (see Display Issues above)
```

---

## Performance Issues

### ⚠️ Statusline slow to update

**Symptom**: Lag between action and statusline refresh

**Cause**: Large transcript file (>10MB) slows parsing.

**Fix**:
```bash
# Check transcript size
du -h ~/.claude/sessions/*/transcript.jsonl

# If >10MB, start new session
# (File menu → New Session)
```

---

### ⚠️ CLI dashboard slow

**Symptom**: `/quota-guard watch` takes >2s to render

**Cause**: Same as above (large transcript).

**Impact**: Not critical, dashboard is read-only.

**Workaround**: Use `/quota-guard query` (faster, no TUI overhead).

---

## Dependency Issues

### ❌ jq not found

**Symptom**: `doctor` shows "jq missing"

**Fix**:
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt install jq

# Arch
sudo pacman -S jq
```

---

### ❌ node/npm not found

**Symptom**: CLI won't build

**Fix**:
```bash
# macOS
brew install node

# Ubuntu/Debian
sudo apt install nodejs npm

# Arch
sudo pacman -S nodejs npm

# Or use nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
nvm install --lts
```

---

## Still Not Working?

### Collect diagnostics

```bash
# Run doctor, save output
/quota-guard doctor > diagnosis.txt

# Check logs
tail -50 ~/.claude/quota-guard.log >> diagnosis.txt

# Check settings
jq '.' ~/.claude/settings.json > settings-dump.json
jq '.' ~/.claude/quota-guard/settings.json >> settings-dump.json
```

### Open an issue

**Before posting**, include:
1. `diagnosis.txt` (from above)
2. Terminal info: `echo "TERM=$TERM COLORTERM=$COLORTERM"`
3. OS: `uname -a`
4. Claude Code version: `claude --version`
5. What you tried

Open at: https://github.com/raylee/claude-quota-guard/issues

---

## Terminal Compatibility Reference

| Terminal | Truecolor | 256-color | 16-color | Notes |
|----------|-----------|-----------|----------|-------|
| iTerm2 (macOS) | ✅ | ✅ | ✅ | Best support |
| Terminal.app | ❌ | ✅ | ✅ | Set TERM=xterm-256color |
| kitty | ✅ | ✅ | ✅ | Full support |
| Alacritty | ✅ | ✅ | ✅ | Full support |
| tmux (default) | ❌ | ✅ | ✅ | See tmux fix above |
| tmux (with Tc) | ✅ | ✅ | ✅ | After config change |
| VS Code terminal | ✅ | ✅ | ✅ | Full support |
| Windows Terminal | ✅ | ✅ | ✅ | Windows 10+ |
| cmd.exe | ❌ | ❌ | ⚠️ | Limited, use WSL |
| PowerShell | ❌ | ✅ | ✅ | Windows 10+ |

**Legend**:
- ✅ Fully supported
- ⚠️ Partially works
- ❌ Not supported

---

## See Also

- [Getting Started](getting-started.md) - Installation guide
- [Skill Commands](../skill/SKILL.md) - Complete command reference
- [Architecture](../CLAUDE.md) - How it works (internals)
