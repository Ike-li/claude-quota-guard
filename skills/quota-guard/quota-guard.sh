#!/usr/bin/env bash
# Claude Quota Guard - Skill Entry Point
# Usage: /quota-guard:quota-guard <command>   (or: bash quota-guard.sh <command>)

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SKILL_DIR/../.." && pwd)"   # repo/plugin root (two levels up from skills/quota-guard/)

cmd="${1:-help}"
shift || true

case "$cmd" in
  setup|install)
    echo "🔧 Installing Claude Quota Guard..."
    bash "$PROJECT_ROOT/install.sh"
    ;;

  watch)
    echo "📊 Launching TUI dashboard..."
    "$PROJECT_ROOT/bin/quota-guard" watch "$@"
    ;;

  query)
    "$PROJECT_ROOT/bin/quota-guard" query "$@"
    ;;

  config)
    config_file="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/quota-guard/settings.json"
    if [ ! -f "$config_file" ]; then
      echo "Creating default config..."
      mkdir -p "$(dirname "$config_file")"
      cp "$PROJECT_ROOT/config/settings.default.json" "$config_file"
    fi
    ${EDITOR:-nano} "$config_file"
    echo "✓ Config saved to: $config_file"
    echo "  Restart Claude Code to apply changes"
    ;;

  theme)
    theme_name="${1:-}"
    if [ -z "$theme_name" ]; then
      echo "Available themes:"
      ls "$PROJECT_ROOT/themes/" | sed 's/\.sh$//' | sed 's/^/  - /'
      echo ""
      echo "Usage: /quota-guard theme <name>"
      exit 0
    fi

    # Validate theme exists
    theme_file="$PROJECT_ROOT/themes/${theme_name}.sh"
    if [ ! -f "$theme_file" ]; then
      echo "❌ Theme not found: $theme_name"
      echo ""
      echo "Available themes:"
      ls "$PROJECT_ROOT/themes/" | sed 's/\.sh$//' | sed 's/^/  - /'
      exit 1
    fi

    config_file="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/quota-guard/settings.json"
    if [ ! -f "$config_file" ]; then
      mkdir -p "$(dirname "$config_file")"
      cp "$PROJECT_ROOT/config/settings.default.json" "$config_file"
    fi

    # Update theme in settings.json
    tmp=$(mktemp)
    jq --arg theme "$theme_name" '.display.statusline.theme = $theme' "$config_file" > "$tmp"
    mv "$tmp" "$config_file"

    echo "✓ Theme set to: $theme_name"
    echo "  Restart Claude Code to see changes"
    ;;

  preset)
    preset_name="${1:-}"
    if [ -z "$preset_name" ]; then
      echo "Available presets:"
      echo "  - minimal  (quota + context only)"
      echo "  - compact  (single line, essential info)"
      echo "  - full     (dual line, all features)"
      echo ""
      echo "Usage: /quota-guard preset <name>"
      exit 0
    fi

    # Validate preset
    case "$preset_name" in
      minimal|compact|full)
        ;;
      *)
        echo "❌ Invalid preset: $preset_name"
        echo ""
        echo "Available presets:"
        echo "  - minimal  (quota + context only)"
        echo "  - compact  (single line, essential info)"
        echo "  - full     (dual line, all features)"
        exit 1
        ;;
    esac

    config_file="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/quota-guard/settings.json"
    if [ ! -f "$config_file" ]; then
      mkdir -p "$(dirname "$config_file")"
      cp "$PROJECT_ROOT/config/settings.default.json" "$config_file"
    fi

    tmp=$(mktemp)
    jq --arg preset "$preset_name" '.display.statusline.preset = $preset' "$config_file" > "$tmp"
    mv "$tmp" "$config_file"

    echo "✓ Preset set to: $preset_name"
    echo "  Restart Claude Code to see changes"
    ;;

  mode)
    # Apply a named capability bundle. The model-driven config flow (SKILL.md)
    # calls this after asking the user which mode they want.
    mode_name="${1:-}"
    config_file="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/quota-guard/settings.json"
    if [ -z "$mode_name" ]; then
      echo "Usage: /quota-guard:quota-guard mode <full|essential|quiet>"
      echo "  full       all data + notices on (default)"
      echo "  essential  context + quota only, compact statusline"
      echo "  quiet      convergence only; no [CTX-NOTICE], minimal statusline"
      exit 0
    fi
    case "$mode_name" in
      full)      filter='.features.ctxNotice=true | .display.statusline.preset="full"    | .display.statusline.elements={context:true,quota:true,git:true,agents:true,todos:true,tokens:true} | .logging.enabled=true' ;;
      essential) filter='.features.ctxNotice=true | .display.statusline.preset="compact" | .display.statusline.elements={context:true,quota:true,git:false,agents:false,todos:false,tokens:false}' ;;
      quiet)     filter='.features.ctxNotice=false | .display.statusline.preset="minimal" | .display.statusline.elements={context:true,quota:false,git:false,agents:false,todos:false,tokens:false}' ;;
      *) echo "❌ Unknown mode: $mode_name (expected full|essential|quiet)"; exit 1 ;;
    esac
    if [ ! -f "$config_file" ]; then
      mkdir -p "$(dirname "$config_file")"
      cp "$PROJECT_ROOT/config/settings.default.json" "$config_file"
    fi
    tmp=$(mktemp)
    jq "$filter" "$config_file" > "$tmp" && mv "$tmp" "$config_file"
    echo "✓ Mode set to: $mode_name"
    echo "  Restart Claude Code to apply"
    ;;

  set)
    # Set a single config key. dotpath is sanitized (it's interpolated into the
    # jq program); the value is type-coerced (true/false→bool, ints→number, else
    # string via --arg, which is injection-safe).
    dotpath="${1:-}"; value="${2:-}"
    config_file="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/quota-guard/settings.json"
    if [ -z "$dotpath" ] || [ "$#" -lt 2 ]; then
      echo "Usage: /quota-guard:quota-guard set <dotpath> <value>"
      echo "  e.g. set display.statusline.elements.git false"
      echo "       set thresholds.ctxHalt 80"
      echo "       set features.ctxNotice false"
      exit 0
    fi
    if ! printf '%s' "$dotpath" | grep -Eq '^[A-Za-z0-9_.]+$'; then
      echo "❌ Invalid key path: $dotpath (allowed: letters, digits, _ and .)"; exit 1
    fi
    if [ ! -f "$config_file" ]; then
      mkdir -p "$(dirname "$config_file")"
      cp "$PROJECT_ROOT/config/settings.default.json" "$config_file"
    fi
    tmp=$(mktemp)
    if [ "$value" = "true" ] || [ "$value" = "false" ] || printf '%s' "$value" | grep -Eq '^-?[0-9]+$'; then
      jq ".${dotpath} = ${value}" "$config_file" > "$tmp"
    else
      jq --arg v "$value" ".${dotpath} = \$v" "$config_file" > "$tmp"
    fi
    if [ -s "$tmp" ]; then
      mv "$tmp" "$config_file"
      echo "✓ set ${dotpath} = ${value}"
      echo "  Restart Claude Code to apply"
    else
      rm -f "$tmp"; echo "❌ Failed to set ${dotpath}"; exit 1
    fi
    ;;

  show)
    # Print the current effective config (human + model readable). The config
    # flow calls this first to show the user their current state.
    config_file="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/quota-guard/settings.json"
    if [ ! -f "$config_file" ]; then
      echo "No settings.json yet — using built-in defaults. Run setup or 'mode full'."
      exit 0
    fi
    echo "Current configuration ($config_file):"
    jq -r '
      "  mode:           \(.mode // "auto")   lang: \(.lang // "en")",
      "  thresholds:     ctxNotice=\(.thresholds.ctxNotice)  ctxHalt=\(.thresholds.ctxHalt)  rateHalt=\(.thresholds.rateHalt)",
      "  features:       ctxNotice=\(if .features.ctxNotice == null then "true" else (.features.ctxNotice|tostring) end)   (guard convergence: always on)",
      "  statusline:     preset=\(.display.statusline.preset)  theme=\(.display.statusline.theme)",
      "  show elements:  " + ([.display.statusline.elements | to_entries[] | select(.value==true) | .key] | join(", ") | if . == "" then "(none)" else . end),
      "  exportJson:     \(.exportJson.enabled)   logging: \(.logging.enabled)"
    ' "$config_file"
    ;;

  doctor)
    echo "🔍 Diagnosing Claude Quota Guard installation..."
    echo ""

    # Check hooks registration
    settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
    if [ ! -f "$settings" ]; then
      echo "❌ settings.json not found"
      exit 1
    fi

    # Check statusLine
    statusline_cmd=$(jq -r '.statusLine.command // empty' "$settings" 2>/dev/null)
    if echo "$statusline_cmd" | grep -q "quota-guard\|collect.sh\|statusline-command.sh"; then
      echo "✓ statusLine hook registered"
      # Check which script is used
      if echo "$statusline_cmd" | grep -q "statusline-command.sh"; then
        echo "  └─ Using: statusline-command.sh (rich display)"
      elif echo "$statusline_cmd" | grep -q "collect.sh"; then
        echo "  └─ Using: collect.sh (minimal display)"
      fi
    else
      echo "❌ statusLine hook not found"
      echo "   Run: /quota-guard setup"
    fi

    # Check UserPromptSubmit
    if jq -e '.hooks.UserPromptSubmit[]?.hooks[]?.command | contains("guard.sh")' "$settings" >/dev/null 2>&1; then
      echo "✓ UserPromptSubmit hook registered"
    else
      echo "❌ UserPromptSubmit hook not found"
      echo "   Run: /quota-guard setup"
    fi

    # Check CLI
    if [ -x "$PROJECT_ROOT/bin/quota-guard" ]; then
      echo "✓ CLI binary found"
      # Check if it actually works
      if "$PROJECT_ROOT/bin/quota-guard" query --json >/dev/null 2>&1; then
        echo "  └─ CLI functional"
      else
        echo "  └─ ⚠️  CLI exists but may have errors"
      fi
    else
      echo "⚠️  CLI not built"
      echo "   Run: cd cli && npm install && npm run build"
    fi

    # Check snapshot
    snapshot="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.quota-now"
    if [ -f "$snapshot" ]; then
      age=$(($(date +%s) - $(stat -f %m "$snapshot" 2>/dev/null || stat -c %Y "$snapshot" 2>/dev/null)))
      if [ "$age" -lt 60 ]; then
        echo "✓ Snapshot fresh (${age}s old)"
      else
        echo "⚠️  Snapshot stale (${age}s old)"
        echo "   Hooks may not be running. Check statusLine config."
      fi
    else
      echo "⚠️  Snapshot not found (hooks may not have run yet)"
    fi

    # Check config
    config_file="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/quota-guard/settings.json"
    if [ -f "$config_file" ]; then
      echo "✓ Config file found"
      # Validate JSON
      if jq empty "$config_file" 2>/dev/null; then
        echo "  └─ JSON valid"
      else
        echo "  └─ ⚠️  JSON syntax error"
      fi
    else
      echo "⚠️  Config file not found (using defaults)"
    fi

    # Check terminal color support
    echo ""
    echo "🎨 Terminal Capability:"
    echo "  TERM=$TERM"
    echo "  COLORTERM=${COLORTERM:-not set}"

    # Detect which tier will be used
    if [[ "$COLORTERM" == "truecolor" ]] || [[ "$COLORTERM" == "24bit" ]]; then
      echo "  └─ ✓ 24-bit truecolor supported"
    elif [[ "$TERM" == *"256color"* ]]; then
      echo "  └─ ✓ 256-color supported"
    else
      echo "  └─ ⚠️  Basic 16-color mode (may look less vibrant)"
    fi

    # Test color rendering
    echo ""
    echo "  Color test:"
    printf "    "
    printf '\033[91m●\033[0m '  # red
    printf '\033[92m●\033[0m '  # green
    printf '\033[94m●\033[0m '  # blue
    printf '\033[93m●\033[0m '  # yellow
    printf '\033[96m●\033[0m '  # cyan
    printf '\033[95m●\033[0m'   # magenta
    echo ""
    echo "  └─ If you see colored circles above, colors work!"
    echo "     If you see [91m● etc, colors are broken."
    echo "     See: docs/troubleshooting.md"

    # Check dependencies
    echo ""
    echo "📦 Dependencies:"
    for cmd in jq node npm; do
      if command -v "$cmd" >/dev/null 2>&1; then
        version=$("$cmd" --version 2>&1 | head -1)
        echo "  ✓ $cmd ($version)"
      else
        echo "  ❌ $cmd missing"
      fi
    done

    echo ""
    echo "📋 Summary:"
    echo "  Project root: $PROJECT_ROOT"
    echo "  Config dir: ${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

    # Overall health check
    echo ""
    statusline_ok=false
    guard_ok=false

    if echo "$statusline_cmd" | grep -q "quota-guard\|collect.sh\|statusline-command.sh"; then
      statusline_ok=true
    fi

    if jq -e '.hooks.UserPromptSubmit[]?.hooks[]?.command | contains("guard.sh")' "$settings" >/dev/null 2>&1; then
      guard_ok=true
    fi

    if [ "$statusline_ok" = true ] && [ "$guard_ok" = true ]; then
      echo "✅ Installation looks healthy!"
      echo "   If statusline doesn't show colors, see docs/troubleshooting.md"
    else
      echo "⚠️  Installation incomplete. Run: /quota-guard setup"
    fi
    ;;

  clean)
    echo "🧹 Cleaning caches..."
    config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    rm -f "$config_dir/.quota-now"
    rm -f "$config_dir/.quota-now-"*
    rm -f "$config_dir/.cqg-notice-stamp"
    rm -f "$config_dir/quota-guard.log"
    rm -f "$config_dir/quota-guard.log.1"
    echo "✓ Caches cleaned"
    ;;

  uninstall)
    echo "🗑️  Uninstalling Claude Quota Guard..."
    bash "$PROJECT_ROOT/uninstall.sh"
    ;;

  help|--help|-h)
    cat <<EOF
Claude Quota Guard - Prevent mid-task quota exhaustion

Usage: /quota-guard:quota-guard <command> [options]

Commands:
  setup            Wire statusLine, build CLI, mark statusLine owner
  config           Guided config (Claude walks you through it in chat)
  mode <name>      Apply a bundle: full | essential | quiet
  set <path> <val> Set one key, e.g. set features.ctxNotice false
  show             Print the current effective configuration
  watch            Launch live TUI dashboard
  query            One-shot session state (text or --json)
  theme <name>     Switch color theme
  preset <name>    Switch display preset (minimal|compact|full)
  doctor           Diagnose installation issues
  clean            Clear all caches
  uninstall        Remove all components (run BEFORE /plugin uninstall)
  help             Show this help

Examples:
  /quota-guard:quota-guard config
  /quota-guard:quota-guard mode essential
  /quota-guard:quota-guard set display.statusline.elements.git false
  /quota-guard:quota-guard show

Documentation: https://github.com/Ike-li/claude-quota-guard
EOF
    ;;

  *)
    echo "Unknown command: $cmd"
    echo "Run '/quota-guard help' for usage"
    exit 1
    ;;
esac
