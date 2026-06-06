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

# ── locate & load config ───────────────────────────────────────────────
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${CQG_CONFIG:-$SELF_DIR/../config.sh}"
[[ -f "$CONFIG" ]] && # shellcheck disable=SC1090
  . "$CONFIG"
: "${CQG_CTX_NOTICE:=50}"; : "${CQG_CTX_HALT:=85}"
: "${CQG_RATE_HALT:=85}"
: "${CQG_LANG:=en}";       : "${CQG_MAX_AGE:=60}"
: "${CQG_SNAPSHOT:=$HOME/.claude/.quota-now}"
: "${CQG_NOTICE_STAMP:=$HOME/.claude/.cqg-notice-stamp}"

# parse session_id from hook JSON; prefer per-session snapshot/stamp so
# concurrent sessions don't overwrite each other's ctx values
_hook_json="$(cat 2>/dev/null || true)"
_session_id=""
if command -v jq >/dev/null 2>&1; then
  _session_id="$(printf '%s' "$_hook_json" | jq -r '.session_id // .sessionId // empty' 2>/dev/null || true)"
fi
if [ -n "$_session_id" ]; then
  _sess_snap="${CQG_SNAPSHOT}-${_session_id}"
  [ -f "$_sess_snap" ] && CQG_SNAPSHOT="$_sess_snap"
  CQG_NOTICE_STAMP="${CQG_NOTICE_STAMP}-${_session_id}"
fi

# ── snapshot must exist, be non-empty, and be fresh ────────────────────
[[ -f "$CQG_SNAPSHOT" && -s "$CQG_SNAPSHOT" ]] || exit 0
now="$(date +%s)"
mtime="$(stat -f %m "$CQG_SNAPSHOT" 2>/dev/null || stat -c %Y "$CQG_SNAPSHOT" 2>/dev/null || echo 0)"
(( now - mtime > CQG_MAX_AGE )) && exit 0

# ── parse fields (awk -F tab is robust to empty fields; read collapses them) ──
f() { awk -F'\t' -v c="$1" 'NR==1{print $c}' "$CQG_SNAPSHOT"; }
usage_5h="$(f 1)"; usage_7d="$(f 2)"; proj_5h="$(f 3)"
five_reset="$(f 4)"; ctx="$(f 6)"

num() { case "$1" in ''|*[!0-9.]*) echo 0 ;; *) echo "$1" ;; esac; }
usage_5h="$(num "$usage_5h")"; proj_5h="$(num "$proj_5h")"; ctx="$(num "$ctx")"

ge() { (( $(echo "$1 >= $2" | bc -l) )); }

# ── API/relay detection: skip rate-limit tier (no 5h/7d concept) ───────
base_url="${ANTHROPIC_BASE_URL:-}"
is_relay=false
if [[ -n "$base_url" && "$base_url" != *"api.anthropic.com"* ]]; then is_relay=true; fi

# ── evaluate tiers ─────────────────────────────────────────────────────
quota_trigger=false
if [[ "$is_relay" == "false" ]]; then
  if ge "$usage_5h" "$CQG_RATE_HALT"; then
    quota_trigger=true
  fi
fi
ctx_trigger=false
ge "$ctx" "$CQG_CTX_HALT" && ctx_trigger=true

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
  echo "---"; echo "$L_HALT_HDR"; echo ""; echo "$L_STATE"
  [[ "$ctx_trigger" == "true" ]] && echo "$L_CTX"
  if [[ "$quota_trigger" == "true" ]]; then
    echo "$L_5H"; echo "$L_PROJ"; echo "$L_RESET"; echo "$L_7D"
  fi
  echo ""; echo "$L_FOOT"; echo "---"
  exit 0
fi

# ── NOTICE tier: [CTX-NOTICE] (once per crossing) ──────────────────────
if ge "$ctx" "$CQG_CTX_NOTICE"; then
  if [[ ! -f "$CQG_NOTICE_STAMP" ]]; then
    : > "$CQG_NOTICE_STAMP"
    echo "---"; echo "$L_NOTICE"; echo "$L_NOTICE2"; echo "---"
  fi
  exit 0
fi

# ── below notice threshold: clear stamp so next crossing re-notices ────
rm -f "$CQG_NOTICE_STAMP" 2>/dev/null || true
exit 0
