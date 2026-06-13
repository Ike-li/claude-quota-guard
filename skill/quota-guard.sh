#!/usr/bin/env bash
# Claude Quota Guard - Skill Entry Point
# Usage: /quota-guard <command>

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SKILL_DIR/.." && pwd)"

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
    if jq -e '.statusLine.command | contains("collect.sh")' "$settings" >/dev/null 2>&1; then
      echo "✓ statusLine hook registered"
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
      fi
    else
      echo "⚠️  Snapshot not found (hooks may not have run yet)"
    fi

    echo ""
    echo "📋 Summary:"
    echo "  Project root: $PROJECT_ROOT"
    echo "  Config dir: ${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
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

Usage: /quota-guard <command> [options]

Commands:
  setup         Install hooks and build CLI
  watch         Launch live TUI dashboard
  query         One-shot session state (text or --json)
  config        Edit settings.json
  theme <name>  Switch color theme
  preset <name> Switch display preset (minimal|compact|full)
  doctor        Diagnose installation issues
  clean         Clear all caches
  uninstall     Remove all components
  help          Show this help

Examples:
  /quota-guard setup
  /quota-guard watch
  /quota-guard theme cyberpunk
  /quota-guard preset minimal

Documentation: https://github.com/raylee/claude-quota-guard
EOF
    ;;

  *)
    echo "Unknown command: $cmd"
    echo "Run '/quota-guard help' for usage"
    exit 1
    ;;
esac
