#!/usr/bin/env bash
# claude-quota-guard :: collect.sh
#
# Configured as Claude Code's statusLine command. Receives the status-line JSON
# on stdin, extracts rate-limit + context-usage fields, and writes a compact
# snapshot to $CQG_SNAPSHOT for guard.sh to read on the next prompt.
#
# Two modes:
#   standalone — prints a minimal status line itself.
#   wrap       — forwards stdin to your existing status line ($CQG_WRAPPED_STATUSLINE)
#                and prints ITS output, so your display is unchanged.
#
# Snapshot format (tab-separated, one line):
#   5h%  7d%  5h_proj%  5h_reset  7d_reset  ctx%
# Fields absent on API/relay mode are written empty.

set -euo pipefail

# ── locate & load config + shared lib ──────────────────────────────────
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${CQG_CONFIG:-$SELF_DIR/../config.sh}"
# shellcheck disable=SC1090
[[ -f "$CONFIG" ]] && . "$CONFIG"
# defaults if config missing
: "${CQG_SNAPSHOT:=$HOME/.claude/.quota-now}"
: "${CQG_WRAPPED_STATUSLINE:=}"
: "${CQG_EXPORT_JSON:=}"   # opt-in JSON export for other tools (empty = off)

# Source shared snapshot logic
# shellcheck disable=SC1091
. "$SELF_DIR/../lib/snapshot.sh"

# ── read stdin once (JSON), keep a copy to forward in wrap mode ─────────
input="$(cat)"

# ── extract fields (requires jq) ───────────────────────────────────────
_HAS_JQ=false
command -v jq >/dev/null 2>&1 && _HAS_JQ=true
extract() {
  # $1 = jq path expression; returns empty if jq unavailable or path missing
  [[ "$_HAS_JQ" == "true" ]] || return 0
  printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null
}

five_h="$(extract '.rate_limits.five_hour.used_percentage')"
five_reset_at="$(extract '.rate_limits.five_hour.resets_at')"
seven_d="$(extract '.rate_limits.seven_day.used_percentage')"
seven_reset_at="$(extract '.rate_limits.seven_day.resets_at')"
ctx="$(extract '.context_window.used_percentage')"

# session id (sanitized for filename use) — lets us write a per-session
# snapshot so concurrent sessions don't clobber each other's ctx value.
session_id="$(extract '.session_id')"
session_id="$(cqg_sanitize_session_id "$session_id")"

# round percentages to integers
intify() { case "$1" in ''|null) echo "" ;; *) printf '%.0f' "$1" 2>/dev/null || echo "" ;; esac; }
five_int="$(intify "$five_h")"
seven_int="$(intify "$seven_d")"
ctx_int="$(intify "$ctx")"

# Native used_percentage can be absent, or 0 meaning "not yet populated":
# on a fresh session or the first frame after a compact, Claude Code may emit
# used_percentage=0 while current_usage already holds the real initial-context
# tokens (system prompt, tools, memory). Recompute from tokens/size so ctx isn't
# under-reported in that window. Mirrors claude-hud's getContextPercent fallback.
if [[ -z "$ctx_int" || "$ctx_int" == "0" ]]; then
  ctx_in="$(extract '.context_window.current_usage.input_tokens')"
  ctx_cc="$(extract '.context_window.current_usage.cache_creation_input_tokens')"
  ctx_cr="$(extract '.context_window.current_usage.cache_read_input_tokens')"
  ctx_size="$(extract '.context_window.context_window_size')"
  ctx_calc="$(awk -v i="${ctx_in:-0}" -v cc="${ctx_cc:-0}" -v cr="${ctx_cr:-0}" -v sz="${ctx_size:-0}" 'BEGIN {
    if (sz <= 0) exit;
    tot = i + cc + cr; if (tot <= 0) exit;
    p = tot / sz * 100; if (p > 100) p = 100;
    printf "%.0f", p;
  }')"
  [[ -n "$ctx_calc" ]] && ctx_int="$ctx_calc"
fi

# ── 5h projection + human-readable reset deltas (delegated to shared lib) ──
five_proj="$(cqg_five_hour_projection "$five_int" "$five_reset_at")"
five_reset="$(cqg_fmt_reset_delta "$five_reset_at")"
seven_reset="$(cqg_fmt_reset_delta "$seven_reset_at")"

# ── write snapshot (delegates to shared lib) ───────────────────────────
cqg_write_snapshot "$five_int" "$seven_int" "$five_proj" "$five_reset" "$seven_reset" "$ctx_int" "$session_id" || {
  printf 'Warning: Failed to write quota snapshot\n' >&2
}

# ── optional JSON export for other tools (no-op unless CQG_EXPORT_JSON set) ──
# Passes raw reset epochs (not the human "3d"/"4h" deltas) so consumers get
# machine-readable timestamps. Non-fatal: never break the status line.
cqg_write_export_json "$five_int" "$seven_int" "$ctx_int" "$five_reset_at" "$seven_reset_at" || true

# ── render the status line ─────────────────────────────────────────────
if [[ -n "$CQG_WRAPPED_STATUSLINE" ]]; then
  # wrap mode: replay original stdin to the user's status line, print its output
  # CQG_WRAPPED_STATUSLINE comes from config.sh (written by install script);
  # trust boundary: user's own config only, not external input.
  printf '%s' "$input" | eval "$CQG_WRAPPED_STATUSLINE"
else
  # standalone mode: minimal one-liner
  line=""
  [[ -n "$ctx_int" ]]  && line="ctx ${ctx_int}%"
  [[ -n "$five_int" ]] && line="${line:+$line · }5h ${five_int}%${five_reset:+ ↻$five_reset}"
  [[ -n "$seven_int" ]] && line="${line:+$line · }7d ${seven_int}%"
  printf '%s\n' "$line"
fi
