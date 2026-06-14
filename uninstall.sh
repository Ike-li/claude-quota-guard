#!/usr/bin/env bash
# claude-quota-guard :: uninstall.sh
# Reverses install.sh: removes the guard hook, restores or clears the statusLine
# (un-wrapping if it was wrapped), and strips the CLAUDE.md protocol block.

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
# Read config from the stable dir first (where install.sh now writes it), then
# fall back to the legacy repo-root location.
CONFIG="$CLAUDE_DIR/quota-guard/config.sh"
[[ -f "$CONFIG" ]] || CONFIG="$SELF_DIR/config.sh"

say() { printf '%s\n' "$*"; }

command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }

# recover wrapped status line (if any) to restore it
wrapped=""
[[ -f "$CONFIG" ]] && wrapped="$(. "$CONFIG" 2>/dev/null; printf '%s' "${CQG_WRAPPED_STATUSLINE:-}")" || true

if [[ -f "$SETTINGS" ]]; then
  cp "$SETTINGS" "$SETTINGS.cqg-backup.$(date +%Y%m%d%H%M%S)"
  tmp="$(mktemp)"
  jq --arg wrapped "$wrapped" '
    # remove our guard hook entry
    (if .hooks.UserPromptSubmit then
       .hooks.UserPromptSubmit |= map(select(
         (.hooks // []) | any(.command? // "" | contains("claude-quota-guard")) | not))
     else . end)
    | (if (.hooks.UserPromptSubmit // []) == [] then del(.hooks.UserPromptSubmit) else . end)
    | (if (.hooks // {}) == {} then del(.hooks) else . end)
    # restore or remove statusLine
    | (if (.statusLine.command? // "" | contains("collect.sh")) then
         (if $wrapped != "" then
            .statusLine = { type: "command", command: $wrapped, refreshInterval: 10 }
          else del(.statusLine) end)
       else . end)
  ' "$SETTINGS" > "$tmp" && mv -f "$tmp" "$SETTINGS"
  say "→ Cleaned settings.json."
  [[ -n "$wrapped" ]] && say "  restored your original status line."
fi

# strip CLAUDE.md block
if [[ -f "$CLAUDE_MD" ]] && grep -q "BEGIN claude-quota-guard" "$CLAUDE_MD"; then
  tmp="$(mktemp)"
  awk '/<!-- BEGIN claude-quota-guard -->/{skip=1} !skip{print} /<!-- END claude-quota-guard -->/{skip=0}' \
    "$CLAUDE_MD" > "$tmp" && mv -f "$tmp" "$CLAUDE_MD"
  say "→ Removed protocol block from CLAUDE.md."
fi

# clean runtime files (globs cover per-session snapshots/stamps and rotated log)
rm -f "$HOME/.claude/.quota-now" "$HOME/.claude/.quota-now-"* \
      "$HOME/.claude/.cqg-notice-stamp" "$HOME/.claude/.cqg-notice-stamp-"* \
      "$HOME/.claude/quota-guard.log" "$HOME/.claude/quota-guard.log.1" 2>/dev/null || true

# Remove the statusLine owner flag so the plugin's SessionStart bridge goes
# inert — otherwise it would keep re-pinning collect.sh into settings.json (a
# "zombie" status line that /plugin uninstall cannot clear). Also drop the wrap
# helper. Run this BEFORE /plugin uninstall.
rm -f "$CLAUDE_DIR/quota-guard/.statusline-owner" \
      "$CLAUDE_DIR/quota-guard/.cqg-wrap.json" 2>/dev/null || true

say ""
say "✅ Uninstalled. Restart Claude Code to apply."
