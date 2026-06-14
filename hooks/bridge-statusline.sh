#!/usr/bin/env bash
# claude-quota-guard :: bridge-statusline.sh
#
# SessionStart hook. Claude Code plugins cannot declare the primary `statusLine`
# in their manifest (only agent/subagentStatusLine — issue #64074), and
# ${CLAUDE_PLUGIN_ROOT} is NOT expanded in the statusLine subprocess (#52079).
# But collect.sh MUST run as the statusLine to read the 5h/7d rate-limit JSON
# (#27508) that lives nowhere else. So we wire it imperatively here, in hook
# context where ${CLAUDE_PLUGIN_ROOT} DOES expand, baking an absolute path.
#
# Idempotent self-heal: re-pins collect.sh if settings.json was partially
# rewritten and stripped the field (#62486) or the plugin path changed on update.
#
# Safety: acts ONLY after the user opts in via `setup` (owner flag); never
# hijacks a foreign statusLine; emits no stdout (pure maintenance).

set -uo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
OWNER_FLAG="$CLAUDE_DIR/quota-guard/.statusline-owner"

# Opt-in gate: do nothing unless the user ran `setup` (which writes this flag).
# This is why /plugin install alone never touches the statusLine.
[[ -f "$OWNER_FLAG" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Resolve collect.sh absolute path. Prefer ${CLAUDE_PLUGIN_ROOT} (expands here);
# fall back to this script's own dir for non-plugin / dev installs.
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null)" || exit 0
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SELF_DIR/.." && pwd)}"
desired="bash $PLUGIN_ROOT/hooks/collect.sh"

[[ -f "$SETTINGS" ]] || printf '{}\n' > "$SETTINGS"
current="$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null || true)"

# Never clobber a foreign statusLine. We manage only collect.sh; wrapping an
# existing line is handled by collect.sh's own CQG_WRAPPED_STATUSLINE (set by setup).
if [[ -n "$current" && "$current" != *"collect.sh"* ]]; then
  exit 0
fi

# Idempotent: write only when the command differs (restores after a strip,
# re-pins after a plugin update). Mirrors install.sh's statusLine block.
if [[ "$current" != "$desired" ]]; then
  tmp="$(mktemp)" || exit 0
  if jq --arg cmd "$desired" \
       '.statusLine = { type: "command", command: $cmd, refreshInterval: 10 }' \
       "$SETTINGS" > "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$SETTINGS" 2>/dev/null || rm -f "$tmp"
  else
    rm -f "$tmp"
  fi
fi
exit 0
