#!/usr/bin/env bash
# claude-quota-guard :: guard.sh
#
# Configured as Claude Code's UserPromptSubmit hook. Reads the snapshot written
# by collect.sh and, when a threshold is crossed, prints a signal to stdout —
# which Claude Code injects into the model's context for this turn.
#
# Tiers:
#   ctx >= CQG_CTX_HALT  OR  5h >= CQG_RATE_HALT  -> [QUOTA-LOW]   (converge)
#   CQG_CTX_NOTICE <= ctx < CQG_CTX_HALT          -> [CTX-NOTICE]  (advise once)
#   otherwise                                     -> silent
#
# Rate-limit tier is skipped on API/relay mode (no real 5h/7d concept).

set -euo pipefail

# ── locate & load config + shared lib ─────────────────────────────────
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${CQG_CONFIG:-$SELF_DIR/../config.sh}"
# shellcheck disable=SC1090
[[ -f "$CONFIG" ]] && . "$CONFIG"
# Load shared library for stat helpers
# shellcheck disable=SC1091
. "$SELF_DIR/../lib/snapshot.sh"
: "${CQG_CTX_NOTICE:=50}"; : "${CQG_CTX_HALT:=85}"
: "${CQG_RATE_HALT:=85}"
: "${CQG_LANG:=en}";       : "${CQG_MAX_AGE:=60}"
: "${CQG_MODE:=auto}"     # auto | subscription | relay
: "${CQG_SNAPSHOT:=$HOME/.claude/.quota-now}"
: "${CQG_NOTICE_STAMP:=$HOME/.claude/.cqg-notice-stamp}"
: "${CQG_LOG:=$HOME/.claude/quota-guard.log}"
: "${CQG_LOG_MAX:=102400}"   # 100 KB before rotation

# Round thresholds to integers — ((...)) arithmetic doesn't handle decimals
# (old ge() used bc -l which did; this keeps backward compatibility)
CQG_CTX_NOTICE="$(printf '%.0f' "$CQG_CTX_NOTICE" 2>/dev/null || echo 50)"
CQG_CTX_HALT="$(printf '%.0f' "$CQG_CTX_HALT" 2>/dev/null || echo 85)"
CQG_RATE_HALT="$(printf '%.0f' "$CQG_RATE_HALT" 2>/dev/null || echo 85)"

# ── logging (single-line structured; rotate at CQG_LOG_MAX) ───────────
_log() {
  [ -z "${CQG_LOG:-}" ] && return 0
  printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$CQG_LOG" 2>/dev/null || true
  local sz
  sz="$(cqg_stat_size "$CQG_LOG")"
  if (( sz > CQG_LOG_MAX )); then mv "$CQG_LOG" "${CQG_LOG}.1" 2>/dev/null || true; fi
}

# ── parse session_id from hook JSON; prefer per-session snapshot/stamp ─
# concurrent sessions don't overwrite each other's ctx values
_hook_json="$(cat 2>/dev/null || true)"
_session_id=""
if command -v jq >/dev/null 2>&1; then
  _session_id="$(printf '%s' "$_hook_json" | jq -r '.session_id // .sessionId // empty' 2>/dev/null || true)"
fi
# Sanitize identically to collect.sh so the per-session snapshot filename matches.
_session_id="$(cqg_sanitize_session_id "$_session_id")"
_snap_label="global"
if [ -n "$_session_id" ]; then
  _sess_snap="${CQG_SNAPSHOT}-${_session_id}"
  if [ -f "$_sess_snap" ]; then
    CQG_SNAPSHOT="$_sess_snap"
    _snap_label="session"
  fi
  CQG_NOTICE_STAMP="${CQG_NOTICE_STAMP}-${_session_id}"
fi

# ── snapshot must exist, be non-empty, and be fresh ────────────────────
if ! [[ -f "$CQG_SNAPSHOT" && -s "$CQG_SNAPSHOT" ]]; then
  _log "sess=${_session_id:-?} snap=missing → exit"
  exit 0
fi
now="$(date +%s)"
mtime="$(cqg_stat_mtime "$CQG_SNAPSHOT")"
if (( now - mtime > CQG_MAX_AGE )); then
  _log "sess=${_session_id:-?} snap=${_snap_label} stale(age=$((now - mtime))s) → exit"
  exit 0
fi

# ── snapshot field indices (tab-separated, single line) ──────────────────
_FLD_5H=1; _FLD_7D=2; _FLD_PROJ=3; _FLD_5H_RESET=4; _FLD_7D_RESET=5; _FLD_CTX=6
_snap_field() { awk -F'\t' -v c="$1" 'NR==1{print $c}' "$CQG_SNAPSHOT"; }
usage_5h="$(_snap_field $_FLD_5H)"; usage_7d="$(_snap_field $_FLD_7D)"
proj_5h="$(_snap_field $_FLD_PROJ)"; five_reset="$(_snap_field $_FLD_5H_RESET)"
ctx="$(_snap_field $_FLD_CTX)"

# ── rate-tier gate: active only when snapshot has real rate-limit data ──
# CQG_MODE: auto (detect from snapshot data) | subscription (force on) | relay (force off)
# In auto mode, we check whether field 1 (5h%) is non-empty — collect.sh writes
# empty rate fields on API/relay mode, so this is a reliable discriminator.
# Must run BEFORE _as_int sanitizes empty→0.
_rate_available=false
case "${CQG_MODE:-auto}" in
  subscription) _rate_available=true ;;
  relay)       _rate_available=false ;;
  *)           [[ -n "$usage_5h" ]] && _rate_available=true ;;
esac

# Coerce to a plain integer safe for ((...)) — strips decimals and rejects
# anything non-numeric (whitespace, multiple dots, garbage) to 0.
_as_int() { printf '%.0f' "$1" 2>/dev/null || echo 0; }
usage_5h="$(_as_int "$usage_5h")"; proj_5h="$(_as_int "$proj_5h")"; ctx="$(_as_int "$ctx")"

# log prefix shared by all remaining decision points
_lp="sess=${_session_id:-?} snap=${_snap_label} ctx=${ctx} 5h=${usage_5h}"

# ── evaluate tiers ─────────────────────────────────────────────────────
quota_trigger=false
if [[ "$_rate_available" == "true" ]]; then
  if (( usage_5h >= CQG_RATE_HALT )); then
    quota_trigger=true
  fi
fi
ctx_trigger=false
(( ctx >= CQG_CTX_HALT )) && ctx_trigger=true

# ── localized strings ──────────────────────────────────────────────────
if [[ "$CQG_LANG" == "zh" ]]; then
  L_HALT_HDR="⚠️  [QUOTA-LOW] 资源接近限制"; L_STATE="当前状态："
  L_CTX="- 上下文使用率: ${ctx}%（即将触发 auto-compact / 丢上下文）"
  L_5H="- 5h 使用率: ${usage_5h}%"; L_PROJ="- 5h 预计到期时: ${proj_5h}%"
  L_RESET="- 5h 重置倒计时: ${five_reset:-?}"; L_7D="- 7d 使用率: ${usage_7d:-?}%"
  L_FOOT="**收敛协议已触发** — 请参照 CLAUDE.md § 额度/上下文收敛协议 执行。"
  L_NOTICE="ℹ️  [CTX-NOTICE] 上下文已用 ${ctx}% —— 仅提示，无需收敛。"
  L_NOTICE2="继续正常工作；到 ${CQG_CTX_HALT}% 时会触发收敛协议。"
else
  L_HALT_HDR="⚠️  [QUOTA-LOW] Resources nearing limit"; L_STATE="Status:"
  L_CTX="- Context usage: ${ctx}% (auto-compact / context loss imminent)"
  L_5H="- 5h usage: ${usage_5h}%"; L_PROJ="- 5h projected at reset: ${proj_5h}%"
  L_RESET="- 5h resets in: ${five_reset:-?}"; L_7D="- 7d usage: ${usage_7d:-?}%"
  L_FOOT="**Convergence protocol triggered** — follow CLAUDE.md § Quota / Context Convergence Protocol."
  L_NOTICE="ℹ️  [CTX-NOTICE] Context at ${ctx}% — advisory only, no convergence."
  L_NOTICE2="Keep working normally; convergence triggers at ${CQG_CTX_HALT}%."
fi

# ── HALT tier: [QUOTA-LOW] ─────────────────────────────────────────────
if [[ "$quota_trigger" == "true" || "$ctx_trigger" == "true" ]]; then
  : > "$CQG_NOTICE_STAMP"   # reset notice dedup so a later drop re-notices
  _reason=""
  [[ "$ctx_trigger"   == "true" ]] && _reason="${_reason}ctx"
  [[ "$quota_trigger" == "true" ]] && _reason="${_reason:+$_reason+}5h"
  _log "$_lp → QUOTA-LOW(${_reason})"
  echo "---"; echo "$L_HALT_HDR"; echo ""; echo "$L_STATE"
  [[ "$ctx_trigger" == "true" ]] && echo "$L_CTX"
  if [[ "$quota_trigger" == "true" ]]; then
    echo "$L_5H"; echo "$L_PROJ"; echo "$L_RESET"; echo "$L_7D"
  fi
  echo ""; echo "$L_FOOT"; echo "---"
  exit 0
fi

# ── NOTICE tier: [CTX-NOTICE] (once per crossing) ──────────────────────
if (( ctx >= CQG_CTX_NOTICE )); then
  if [[ ! -f "$CQG_NOTICE_STAMP" ]]; then
    : > "$CQG_NOTICE_STAMP"
    _log "$_lp → CTX-NOTICE"
    echo "---"; echo "$L_NOTICE"; echo "$L_NOTICE2"; echo "---"
  else
    _log "$_lp → silent(dedup)"
  fi
  exit 0
fi

# ── below notice threshold: clear stamp so next crossing re-notices ────
rm -f "$CQG_NOTICE_STAMP" 2>/dev/null || true
_log "$_lp → silent(ctx<${CQG_CTX_NOTICE})"
exit 0
