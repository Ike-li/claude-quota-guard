#!/bin/bash
# Config Loader - Reads settings.json and exports as environment variables
# Falls back to config.sh for backward compatibility

set -euo pipefail

CQG_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/quota-guard"
CQG_CONFIG_JSON="$CQG_CONFIG_DIR/settings.json"
CQG_CONFIG_LEGACY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config.sh"

# Helper: read JSON value with fallback
json_get() {
  local path="$1"
  local default="$2"
  if [ -f "$CQG_CONFIG_JSON" ] && command -v jq >/dev/null 2>&1; then
    jq -r "$path // \"$default\"" "$CQG_CONFIG_JSON" 2>/dev/null || echo "$default"
  else
    echo "$default"
  fi
}

# Load legacy config.sh if it exists and JSON doesn't
if [ ! -f "$CQG_CONFIG_JSON" ] && [ -f "$CQG_CONFIG_LEGACY" ]; then
  source "$CQG_CONFIG_LEGACY"
else
  # Load from JSON
  export CQG_CTX_NOTICE=$(json_get '.thresholds.ctxNotice' '50')
  export CQG_CTX_HALT=$(json_get '.thresholds.ctxHalt' '85')
  export CQG_RATE_HALT=$(json_get '.thresholds.rateHalt' '85')
  export CQG_MODE=$(json_get '.mode' 'auto')
  export CQG_LANG=$(json_get '.lang' 'en')

  # Display settings
  export CQG_STATUSLINE_PRESET=$(json_get '.display.statusline.preset' 'full')
  export CQG_STATUSLINE_THEME=$(json_get '.display.statusline.theme' 'catppuccin-mocha')
  export CQG_STATUSLINE_RESPONSIVE=$(json_get '.display.statusline.responsive' 'true')

  export CQG_SHOW_CONTEXT=$(json_get '.display.statusline.elements.context' 'true')
  export CQG_SHOW_QUOTA=$(json_get '.display.statusline.elements.quota' 'true')
  export CQG_SHOW_GIT=$(json_get '.display.statusline.elements.git' 'true')
  export CQG_SHOW_AGENTS=$(json_get '.display.statusline.elements.agents' 'true')
  export CQG_SHOW_TODOS=$(json_get '.display.statusline.elements.todos' 'true')
  export CQG_SHOW_TOKENS=$(json_get '.display.statusline.elements.tokens' 'true')

  # Snapshot settings
  export CQG_MAX_AGE=$(json_get '.snapshot.maxAge' '60')
  export CQG_SWEEP_RATE=$(json_get '.snapshot.sweepRate' '100')
  export CQG_SWEEP_MAX_AGE_DAYS=$(json_get '.snapshot.sweepMaxAgeDays' '7')

  # Logging
  CQG_LOG_ENABLED=$(json_get '.logging.enabled' 'true')
  if [ "$CQG_LOG_ENABLED" = "true" ]; then
    CQG_LOG_PATH=$(json_get '.logging.path' 'null')
    if [ "$CQG_LOG_PATH" = "null" ]; then
      export CQG_LOG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/quota-guard.log"
    else
      export CQG_LOG="$CQG_LOG_PATH"
    fi
    export CQG_LOG_MAX=$(json_get '.logging.maxSize' '102400')
  else
    export CQG_LOG=""
  fi

  # Export JSON
  CQG_EXPORT_ENABLED=$(json_get '.exportJson.enabled' 'false')
  if [ "$CQG_EXPORT_ENABLED" = "true" ]; then
    CQG_EXPORT_PATH=$(json_get '.exportJson.path' 'null')
    if [ "$CQG_EXPORT_PATH" != "null" ]; then
      export CQG_EXPORT_JSON="$CQG_EXPORT_PATH"
    fi
  fi
fi

# Load theme if specified
THEME_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/themes/${CQG_STATUSLINE_THEME:-catppuccin-mocha}.sh"
if [ -f "$THEME_FILE" ]; then
  source "$THEME_FILE"
fi
