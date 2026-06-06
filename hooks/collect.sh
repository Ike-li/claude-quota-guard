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

# ── locate & load config ───────────────────────────────────────────────
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${CQG_CONFIG:-$SELF_DIR/../config.sh}"
[[ -f "$CONFIG" ]] && # shellcheck disable=SC1090
  . "$CONFIG"
# defaults if config missing
: "${CQG_SNAPSHOT:=$HOME/.claude/.quota-now}"
: "${CQG_WRAPPED_STATUSLINE:=}"

# ── read stdin once (JSON), keep a copy to forward in wrap mode ─────────
input="$(cat)"

# ── extract fields (jq if available, else grep/sed fallback) ───────────
extract() {
  # $1 = jq path expression
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null
  fi
}

five_h="$(extract '.rate_limits.five_hour.used_percentage')"
five_reset_at="$(extract '.rate_limits.five_hour.resets_at')"
seven_d="$(extract '.rate_limits.seven_day.used_percentage')"
seven_reset_at="$(extract '.rate_limits.seven_day.resets_at')"
ctx="$(extract '.context_window.used_percentage')"

# session id (sanitized for filename use) — lets us write a per-session
# snapshot so concurrent sessions don't clobber each other's ctx value.
session_id="$(extract '.session_id')"
session_id="$(printf '%s' "$session_id" | tr -cd 'A-Za-z0-9_.-')"

# round percentages to integers
intify() { case "$1" in ''|null) echo "" ;; *) printf '%.0f' "$1" 2>/dev/null || echo "" ;; esac; }
five_int="$(intify "$five_h")"
seven_int="$(intify "$seven_d")"
ctx_int="$(intify "$ctx")"

# ── 5h projection: at current burn, where we'll land by window reset ────
# 5h window = 18000s. Only meaningful once enough of the window has elapsed.
five_proj=""
if [[ -n "$five_int" && -n "$five_reset_at" ]]; then
  five_proj="$(awk -v used="$five_int" -v reset="$five_reset_at" -v now="$(date +%s)" 'BEGIN {
    win = 18000; remain = reset - now; elapsed = win - remain;
    if (elapsed < 300 || used <= 0) exit;
    p = used * win / elapsed; if (p > 999) p = 999;
    printf "%.0f", p;
  }')"
fi

# ── human-readable reset deltas ────────────────────────────────────────
delta() {
  local epoch="$1" now
  [[ -n "$epoch" ]] || { echo ""; return; }
  now="$(date +%s)"
  awk -v e="$epoch" -v n="$now" 'BEGIN {
    s = e - n; if (s <= 0) { print "now"; exit }
    if (s >= 86400) printf "%dd", int(s/86400);
    else if (s >= 3600) printf "%dh", int(s/3600);
    else if (s >= 60) printf "%dm", int(s/60);
    else printf "%ds", s;
  }'
}
five_reset="$(delta "$five_reset_at")"
seven_reset="$(delta "$seven_reset_at")"

# ── write snapshot atomically (global + per-session) ───────────────────
# The per-session file (.quota-now-<id>) lets guard.sh read THIS session's
# ctx even when multiple sessions run concurrently and clobber the global one.
# guard.sh prefers the per-session file and falls back to the global one.
snap_line="$(printf '%s\t%s\t%s\t%s\t%s\t%s' \
  "$five_int" "$seven_int" "$five_proj" "$five_reset" "$seven_reset" "$ctx_int")"
write_snap() {
  local dest="$1" tmp
  tmp="$(mktemp "${dest}.XXXXXX" 2>/dev/null || echo "${dest}.tmp")"
  printf '%s\n' "$snap_line" > "$tmp"
  mv -f "$tmp" "$dest"
}
write_snap "$CQG_SNAPSHOT"
[[ -n "$session_id" ]] && write_snap "${CQG_SNAPSHOT}-${session_id}"

# ── render the status line ─────────────────────────────────────────────
if [[ -n "$CQG_WRAPPED_STATUSLINE" ]]; then
  # wrap mode: replay original stdin to the user's status line, print its output
  printf '%s' "$input" | eval "$CQG_WRAPPED_STATUSLINE"
else
  # standalone mode: minimal one-liner
  line=""
  [[ -n "$ctx_int" ]]  && line="ctx ${ctx_int}%"
  [[ -n "$five_int" ]] && line="${line:+$line · }5h ${five_int}%${five_reset:+ ↻$five_reset}"
  [[ -n "$seven_int" ]] && line="${line:+$line · }7d ${seven_int}%"
  printf '%s\n' "$line"
fi
