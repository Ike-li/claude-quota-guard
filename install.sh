#!/usr/bin/env bash
# claude-quota-guard :: install.sh
# Interactive installer. Wires collect.sh as the statusLine command and guard.sh
# as a UserPromptSubmit hook, installs config, and appends the convergence
# protocol to your user CLAUDE.md. Idempotent — safe to re-run.

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
CONFIG="$SELF_DIR/config.sh"

say() { printf '%s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; }

# ── 1. dependency check ────────────────────────────────────────────────
say "→ Checking dependencies..."
missing=()
for c in bash awk date stat jq; do
  command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done
if (( ${#missing[@]} )); then
  err "Missing required commands: ${missing[*]}"
  err "Install them and re-run. (jq is required to safely edit settings.json.)"
  exit 1
fi
say "  ✓ all present"

mkdir -p "$CLAUDE_DIR"

# ── 2. config ──────────────────────────────────────────────────────────
if [[ -f "$CONFIG" ]]; then
  say "→ config.sh already exists, keeping it."
else
  cp "$SELF_DIR/config.example.sh" "$CONFIG"
  say "→ Installed config.sh (edit thresholds/language there)."
fi

# ── 3. language choice ─────────────────────────────────────────────────
lang="en"
if [[ -t 0 ]]; then
  printf 'Signal language? [en/zh] (default en): '
  read -r ans || true
  [[ "$ans" == "zh" ]] && lang="zh"
fi
# persist lang into config.sh
if grep -q '^: "${CQG_LANG' "$CONFIG"; then
  sed -i.bak "s/CQG_LANG:=[a-z]*/CQG_LANG:=$lang/" "$CONFIG" && rm -f "$CONFIG.bak"
fi
say "→ Language: $lang"

# ── 4. settings.json: detect existing statusLine → wrap or standalone ───
[[ -f "$SETTINGS" ]] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.cqg-backup.$(date +%Y%m%d%H%M%S)"

existing_sl="$(jq -r '.statusLine.command // empty' "$SETTINGS")"
wrap_cmd=""
if [[ -n "$existing_sl" && "$existing_sl" != *"collect.sh"* ]]; then
  mode="standalone"
  if [[ -t 0 ]]; then
    say "→ Found an existing status line:"
    say "    $existing_sl"
    printf 'Wrap it (keep your display) or replace it? [wrap/replace] (default wrap): '
    read -r ans || true
    [[ "$ans" == "replace" ]] || mode="wrap"
  else
    mode="wrap"
  fi
  [[ "$mode" == "wrap" ]] && wrap_cmd="$existing_sl"
fi
if [[ -n "$wrap_cmd" ]]; then
  say "→ Wrapping existing status line."
else
  say "→ Standalone status line."
fi

# persist wrapped command into config.sh safely (via jq to avoid shell metachar issues)
wrap_json="$SELF_DIR/.cqg-wrap.json"
jq -n --arg cmd "$wrap_cmd" '{wrapped: $cmd}' > "$wrap_json"
# update config.sh to source the JSON-escaped value
if ! grep -q "CQG_WRAPPED_STATUSLINE=" "$CONFIG" 2>/dev/null; then
  cat >> "$CONFIG" <<'EOF'
# Wrapped statusLine command (if wrap mode was chosen during install)
CQG_WRAPPED_STATUSLINE="$(jq -r '.wrapped // ""' "$(dirname "${BASH_SOURCE[0]}")/.cqg-wrap.json" 2>/dev/null || true)"
EOF
fi

# ── 5. write settings.json with jq (idempotent) ────────────────────────
collect="bash $SELF_DIR/hooks/collect.sh"
# The trailing "# claude-quota-guard" is a stable marker: install/uninstall
# match it to find our hook regardless of where the repo was cloned. (It's a
# shell comment, so it doesn't affect execution; guard.sh ignores argv.)
guard="bash $SELF_DIR/hooks/guard.sh # claude-quota-guard"

tmp="$(mktemp)"
jq --arg collect "$collect" --arg guard "$guard" '
  .statusLine = { type: "command", command: $collect, refreshInterval: 10 }
  | .hooks = (.hooks // {})
  | .hooks.UserPromptSubmit = (
      # drop any prior cqg guard entry, then add ours
      ((.hooks.UserPromptSubmit // [])
        | map(select(
            (.hooks // []) | any(.command? // "" | contains("claude-quota-guard")) | not
          )))
      + [ { hooks: [ { type: "command", command: $guard } ] } ]
    )
' "$SETTINGS" > "$tmp" && mv -f "$tmp" "$SETTINGS"
say "→ Updated settings.json (statusLine + UserPromptSubmit hook)."

# ── 6. append convergence protocol to CLAUDE.md ────────────────────────
tpl="$SELF_DIR/templates/convergence.$lang.md"
touch "$CLAUDE_MD"
if grep -q "BEGIN claude-quota-guard" "$CLAUDE_MD"; then
  say "→ CLAUDE.md already has the protocol block, skipping."
else
  printf '\n' >> "$CLAUDE_MD"
  cat "$tpl" >> "$CLAUDE_MD"
  say "→ Appended convergence protocol to CLAUDE.md."
fi

say ""
say "✅ Installed. Restart Claude Code (or start a new session) to activate."
say "   Backup of settings.json saved alongside it (*.cqg-backup.*)."
