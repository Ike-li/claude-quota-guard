#!/usr/bin/env bash
# claude-quota-guard :: install.sh
# Interactive installer. Wires collect.sh as the statusLine command and guard.sh
# as a UserPromptSubmit hook, installs config, and appends the convergence
# protocol to your user CLAUDE.md. Idempotent — safe to re-run.

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
CONFIG="$CLAUDE_DIR/quota-guard/config.sh"   # stable dir — never the ephemeral plugin dir

say() { printf '%s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; }

# ── 1. dependency check ────────────────────────────────────────────────
say "→ Checking dependencies..."
missing=()
for c in bash awk date stat jq node npm; do
  command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done
if (( ${#missing[@]} )); then
  err "Missing required commands: ${missing[*]}"
  err "Install them and re-run. (jq: settings.json editing; node+npm: cli build.)"
  exit 1
fi
say "  ✓ all present"

mkdir -p "$CLAUDE_DIR"

# ── 2. config ──────────────────────────────────────────────────────────
# Create JSON config directory
QG_CONFIG_DIR="$CLAUDE_DIR/quota-guard"
mkdir -p "$QG_CONFIG_DIR"

# Install JSON config if missing
JSON_CONFIG="$QG_CONFIG_DIR/settings.json"
if [[ ! -f "$JSON_CONFIG" ]]; then
  cp "$SELF_DIR/config/settings.default.json" "$JSON_CONFIG"
  JSON_FRESH=true
  say "→ Installed settings.json"
else
  JSON_FRESH=false
  say "→ settings.json already exists, keeping it."
fi

# Keep legacy config.sh for backward compatibility
if [[ -f "$CONFIG" ]]; then
  say "→ config.sh already exists, keeping it."
else
  cp "$SELF_DIR/config.example.sh" "$CONFIG"
  say "→ Installed config.sh (legacy, settings.json takes precedence)."
fi

# ── 3. language choice ─────────────────────────────────────────────────
lang="en"
if [[ -t 0 ]]; then
  printf 'Signal language? [en/zh] (default en): '
  read -r ans || true
  [[ "$ans" == "zh" ]] && lang="zh"
fi

# persist lang into JSON config
tmp=$(mktemp)
jq --arg lang "$lang" '.lang = $lang' "$JSON_CONFIG" > "$tmp" && mv "$tmp" "$JSON_CONFIG"
say "→ Language: $lang"

# ── 3b. capability mode (fresh config only; never clobber an existing one) ─
if [[ "$JSON_FRESH" == true ]]; then
  mode_choice="full"
  if [[ -t 0 ]]; then
    say ""
    say "Which capabilities to enable?"
    say "  full       (default) all data + notices on"
    say "  essential  context + quota only, compact statusline"
    say "  quiet      convergence only; no notices, minimal statusline"
    printf 'Mode? [full/essential/quiet] (Enter = full): '
    read -r ans || true
    case "$ans" in essential|quiet) mode_choice="$ans" ;; *) mode_choice="full" ;; esac
  else
    say "→ Non-interactive: defaulting to mode 'full'."
  fi
  # Reuse the dispatcher's named-bundle definitions (single source of truth).
  CLAUDE_CONFIG_DIR="$CLAUDE_DIR" bash "$SELF_DIR/skills/quota-guard/quota-guard.sh" mode "$mode_choice" >/dev/null 2>&1 || true
  say "→ Capability mode: $mode_choice  (change anytime: /quota-guard:quota-guard config)"
else
  say "→ Keeping your existing config. Reconfigure: /quota-guard:quota-guard config"
fi

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
wrap_json="$QG_CONFIG_DIR/.cqg-wrap.json"
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

# ── 6. mark statusLine ownership ───────────────────────────────────────
# Lets the plugin's SessionStart bridge (hooks/bridge-statusline.sh) re-pin /
# self-heal collect.sh after settings-rewrite strips or plugin-path changes.
# Without this flag the bridge stays inert, so /plugin install alone never
# touches the statusLine.
: > "$QG_CONFIG_DIR/.statusline-owner"
say "→ Marked statusLine owner (enables plugin SessionStart self-heal)."

# Note: the convergence protocol is intentionally NOT written to your CLAUDE.md.
# guard.sh emits it inline (templates/convergence.*.md) only when [QUOTA-LOW]
# actually fires — nothing is injected into your context until then.

# ── 7. build cli + symlink to PATH ─────────────────────────────────────
say "→ Building the dashboard CLI (cli/)..."
(cd "$SELF_DIR/cli" && npm ci --silent && npm run build --silent) || {
  err "CLI build failed. Check that Node ≥18 is installed and cli/package.json is intact."
  exit 1
}
say "  ✓ built dist/cli.js"

BIN_TARGET="$HOME/.local/bin"
mkdir -p "$BIN_TARGET"
ln -sf "$SELF_DIR/bin/quota-guard" "$BIN_TARGET/quota-guard"
say "  ✓ symlinked $BIN_TARGET/quota-guard → bin/quota-guard"

# Advise if ~/.local/bin is not on PATH (common on fresh systems).
if [[ ":$PATH:" != *":$BIN_TARGET:"* ]]; then
  say ""
  say "⚠️  $BIN_TARGET is not on your \$PATH."
  say "   Add it to use 'quota-guard' directly (no path prefix):"
  say "     echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.$(basename "$SHELL")rc"
  say "     source ~/.$(basename "$SHELL")rc"
fi

say ""
say "✅ Installed. Restart Claude Code (or start a new session) to activate."
say "   Backup of settings.json saved alongside it (*.cqg-backup.*)."
