#!/bin/bash
# Config Loader — the SINGLE source of config resolution, sourced by guard.sh,
# collect.sh, and statusline-command.sh. Resolves everything into exported
# CQG_* environment variables.
#
# Precedence (highest first):
#   1. CQG_CONFIG set  → legacy/isolated mode: source that file (if it exists)
#                        and SKIP settings.json entirely. Used by the test suite
#                        (passes an isolated config.sh) and power users; setting
#                        it to a nonexistent path yields a clean, config-less run.
#   2. individual CQG_* already in the environment (the "override via env" contract).
#   3. settings.json    — the authoritative config edited by the config flow.
#   4. config.sh baseline (stable dir, else legacy repo root) — carries
#      CQG_WRAPPED_STATUSLINE (wrap mode lives ONLY here, not in JSON) + legacy values.
#   5. built-in defaults.

set -euo pipefail

CQG_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/quota-guard"
CQG_CONFIG_JSON="$CQG_CONFIG_DIR/settings.json"
_CQG_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CQG_CONFIG_STABLE_SH="$CQG_CONFIG_DIR/config.sh"
CQG_CONFIG_LEGACY_SH="$_CQG_REPO_ROOT/config.sh"

if [ -n "${CQG_CONFIG:-}" ]; then
  # ── Path 1: explicit config file → legacy-only, no JSON ────────────────
  # shellcheck disable=SC1090
  [ -f "$CQG_CONFIG" ] && . "$CQG_CONFIG"
else
  # Snapshot genuine env overrides BEFORE sourcing config.sh, so env wins over JSON.
  _env_ctx_notice="${CQG_CTX_NOTICE:-}";   _env_ctx_halt="${CQG_CTX_HALT:-}"
  _env_rate_halt="${CQG_RATE_HALT:-}";     _env_mode="${CQG_MODE:-}"
  _env_lang="${CQG_LANG:-}";               _env_max_age="${CQG_MAX_AGE:-}"
  _env_sweep_rate="${CQG_SWEEP_RATE:-}";   _env_sweep_days="${CQG_SWEEP_MAX_AGE_DAYS:-}"
  _env_feat_notice="${CQG_FEATURE_CTX_NOTICE:-}"; _env_export="${CQG_EXPORT_JSON:-}"

  # ── Path 4 baseline: config.sh (stable dir first, then legacy repo root) ─
  # Provides CQG_WRAPPED_STATUSLINE + any legacy values. config.sh uses
  # `: "${X:=...}"` so it never clobbers a value already in the environment.
  if [ -f "$CQG_CONFIG_STABLE_SH" ]; then
    # shellcheck disable=SC1090
    . "$CQG_CONFIG_STABLE_SH"
  elif [ -f "$CQG_CONFIG_LEGACY_SH" ]; then
    # shellcheck disable=SC1090
    . "$CQG_CONFIG_LEGACY_SH"
  fi

  # ── Read ALL of settings.json in ONE jq pass into J_* shell vars ────────
  # collect.sh runs as the statusLine every ~10s, so this used to spawn ~15 jq
  # processes per render; now it's one. Each present key emits `J_<name>=<value>`
  # (shell-quoted via tostring|@sh, eval-safe — keys are hardcoded, values escaped);
  # null/absent keys are omitted so the `${J_x:-...}` fallbacks below take over.
  # We deliberately avoid jq's `//` operator: `false // x` → x would silently flip
  # every boolean toggle to its default. A null check selects which lines to emit.
  if [ -f "$CQG_CONFIG_JSON" ] && command -v jq >/dev/null 2>&1; then
    eval "$(jq -r '
      def e($n; $v): if $v == null then empty else "J_\($n)=" + (($v|tostring)|@sh) end;
      e("ctxNotice"; .thresholds.ctxNotice),
      e("ctxHalt"; .thresholds.ctxHalt),
      e("rateHalt"; .thresholds.rateHalt),
      e("mode"; .mode),
      e("lang"; .lang),
      e("featNotice"; .features.ctxNotice),
      e("preset"; .display.statusline.preset),
      e("theme"; .display.statusline.theme),
      e("responsive"; .display.statusline.responsive),
      e("showContext"; .display.statusline.elements.context),
      e("showQuota"; .display.statusline.elements.quota),
      e("showGit"; .display.statusline.elements.git),
      e("showAgents"; .display.statusline.elements.agents),
      e("showTodos"; .display.statusline.elements.todos),
      e("showTokens"; .display.statusline.elements.tokens),
      e("maxAge"; .snapshot.maxAge),
      e("sweepRate"; .snapshot.sweepRate),
      e("sweepDays"; .snapshot.sweepMaxAgeDays),
      e("logEnabled"; .logging.enabled),
      e("logMaxSize"; .logging.maxSize),
      e("logPath"; .logging.path),
      e("exportEnabled"; .exportJson.enabled),
      e("exportPath"; .exportJson.path)
    ' "$CQG_CONFIG_JSON" 2>/dev/null)" || true
  fi

  # ── Precedence: env > JSON (J_*) > config.sh value (CQG_*) > default ─────
  export CQG_CTX_NOTICE="${_env_ctx_notice:-${J_ctxNotice:-${CQG_CTX_NOTICE:-50}}}"
  export CQG_CTX_HALT="${_env_ctx_halt:-${J_ctxHalt:-${CQG_CTX_HALT:-85}}}"
  export CQG_RATE_HALT="${_env_rate_halt:-${J_rateHalt:-${CQG_RATE_HALT:-85}}}"
  export CQG_MODE="${_env_mode:-${J_mode:-${CQG_MODE:-auto}}}"
  export CQG_LANG="${_env_lang:-${J_lang:-${CQG_LANG:-en}}}"
  export CQG_FEATURE_CTX_NOTICE="${_env_feat_notice:-${J_featNotice:-${CQG_FEATURE_CTX_NOTICE:-true}}}"

  # Display (JSON > config.sh/default; mirrors prior behavior — no separate env layer)
  export CQG_STATUSLINE_PRESET="${J_preset:-${CQG_STATUSLINE_PRESET:-full}}"
  export CQG_STATUSLINE_THEME="${J_theme:-${CQG_STATUSLINE_THEME:-catppuccin-mocha}}"
  export CQG_STATUSLINE_RESPONSIVE="${J_responsive:-${CQG_STATUSLINE_RESPONSIVE:-true}}"
  export CQG_SHOW_CONTEXT="${J_showContext:-${CQG_SHOW_CONTEXT:-true}}"
  export CQG_SHOW_QUOTA="${J_showQuota:-${CQG_SHOW_QUOTA:-true}}"
  export CQG_SHOW_GIT="${J_showGit:-${CQG_SHOW_GIT:-true}}"
  export CQG_SHOW_AGENTS="${J_showAgents:-${CQG_SHOW_AGENTS:-true}}"
  export CQG_SHOW_TODOS="${J_showTodos:-${CQG_SHOW_TODOS:-true}}"
  export CQG_SHOW_TOKENS="${J_showTokens:-${CQG_SHOW_TOKENS:-true}}"

  # Snapshot
  export CQG_MAX_AGE="${_env_max_age:-${J_maxAge:-${CQG_MAX_AGE:-60}}}"
  export CQG_SWEEP_RATE="${_env_sweep_rate:-${J_sweepRate:-${CQG_SWEEP_RATE:-100}}}"
  export CQG_SWEEP_MAX_AGE_DAYS="${_env_sweep_days:-${J_sweepDays:-${CQG_SWEEP_MAX_AGE_DAYS:-7}}}"

  # Logging — impose JSON's choice only when a JSON config exists and CQG_LOG
  # isn't already set. Empty CQG_LOG = logging off.
  if [ -f "$CQG_CONFIG_JSON" ] && [ -z "${CQG_LOG:-}" ]; then
    if [ "${J_logEnabled:-true}" = "true" ]; then
      if [ -z "${J_logPath:-}" ] || [ "${J_logPath:-}" = "null" ]; then
        export CQG_LOG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/quota-guard.log"
      else
        export CQG_LOG="$J_logPath"
      fi
      export CQG_LOG_MAX="${CQG_LOG_MAX:-${J_logMaxSize:-102400}}"
    else
      export CQG_LOG=""   # explicitly disabled
    fi
  fi

  # Export JSON bridge — env wins; otherwise enable from JSON when requested.
  if [ -z "${_env_export}" ] && [ "${J_exportEnabled:-false}" = "true" ]; then
    if [ -n "${J_exportPath:-}" ] && [ "${J_exportPath:-}" != "null" ]; then
      export CQG_EXPORT_JSON="$J_exportPath"
    fi
  fi
fi

# ── Theme: define CQG_THEME_* colors for statusline-command.sh. Harmless for
# guard.sh/collect.sh (they ignore these vars). ─────────────────────────────
THEME_FILE="$_CQG_REPO_ROOT/themes/${CQG_STATUSLINE_THEME:-catppuccin-mocha}.sh"
# shellcheck disable=SC1090
[ -f "$THEME_FILE" ] && . "$THEME_FILE"
