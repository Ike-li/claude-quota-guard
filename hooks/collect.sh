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
: "${CQG_NOTICE_STAMP:=$HOME/.claude/.cqg-notice-stamp}"  # guard's stamp base; collect only sweeps its per-session siblings
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

# Pull the raw context-window token counters once; shared by the fallback
# (native missing) and the suspicious-zero guard (native present but glitchy).
ctx_in="$(extract '.context_window.current_usage.input_tokens')"
ctx_out="$(extract '.context_window.current_usage.output_tokens')"
ctx_cc="$(extract '.context_window.current_usage.cache_creation_input_tokens')"
ctx_cr="$(extract '.context_window.current_usage.cache_read_input_tokens')"
ctx_size="$(extract '.context_window.context_window_size')"

# Native used_percentage can be absent, or 0 meaning "not yet populated":
# on a fresh session or the first frame after a compact, Claude Code may emit
# used_percentage=0 while current_usage already holds the real initial-context
# tokens (system prompt, tools, memory). Recompute from tokens/size so ctx isn't
# under-reported in that window. Mirrors claude-hud's getContextPercent fallback.
if [[ -z "$ctx_int" || "$ctx_int" == "0" ]]; then
  ctx_calc="$(awk -v i="${ctx_in:-0}" -v cc="${ctx_cc:-0}" -v cr="${ctx_cr:-0}" -v sz="${ctx_size:-0}" 'BEGIN {
    if (sz <= 0) exit;
    tot = i + cc + cr; if (tot <= 0) exit;
    p = tot / sz * 100; if (p > 100) p = 100;
    printf "%.0f", p;
  }')"
  [[ -n "$ctx_calc" ]] && ctx_int="$ctx_calc"
fi

# Suspicious-zero guard: a frame where ctx is 0/absent *and* every current_usage
# counter is zero, yet a real context_window block exists (size > 0), is a Claude
# Code reporting glitch — not a genuinely empty context (a live session always
# holds system-prompt/tool tokens). Writing it would clobber the good snapshot
# with ctx=0 and mislead guard.sh into "context empty". When detected we skip the
# snapshot/export write so the previous frame survives and ages out naturally
# (fail-safe via CQG_MAX_AGE). The `size > 0` gate means relay/no-context-window
# frames (rate-only) are NOT suppressed, and a genuinely fresh session simply has
# no prior snapshot to protect — skipping is correct there too.
suspicious_zero=false
if [[ -z "$ctx_int" || "$ctx_int" == "0" ]]; then
  suspicious_zero="$(awk -v sz="${ctx_size:-0}" -v i="${ctx_in:-0}" -v o="${ctx_out:-0}" \
    -v cc="${ctx_cc:-0}" -v cr="${ctx_cr:-0}" 'BEGIN {
    print (sz+0 > 0 && i+0==0 && o+0==0 && cc+0==0 && cr+0==0) ? "true" : "false";
  }')"
fi

# ── 5h projection + human-readable reset deltas (delegated to shared lib) ──
five_proj="$(cqg_five_hour_projection "$five_int" "$five_reset_at")"
five_reset="$(cqg_fmt_reset_delta "$five_reset_at")"
seven_reset="$(cqg_fmt_reset_delta "$seven_reset_at")"

# ── extract activity state (running agents + pending todos) ────────────
# Delegate to quota-guard cli (already parses transcript); falls back to 0|0
# if cli unavailable or transcript missing. Non-fatal: activity is advisory.
agents_running=0
todos_pending=0
if command -v quota-guard >/dev/null 2>&1; then
  activity_out="$(quota-guard _activity ${session_id:+--session "$session_id"} 2>/dev/null || echo "0	0")"
  agents_running="$(printf '%s' "$activity_out" | awk -F'\t' '{print $1+0}')"
  todos_pending="$(printf '%s' "$activity_out" | awk -F'\t' '{print $2+0}')"
else
  # Log when quota-guard isn't available — user should know activity tracking is offline
  printf 'Notice: quota-guard cli not found; activity tracking disabled (agents/todos always 0)\n' >&2
fi

# ── write snapshot + export (skipped on a suspicious-zero glitch frame) ─
if [[ "$suspicious_zero" == "true" ]]; then
  # Glitch frame: keep the previous snapshot rather than clobber it with ctx=0.
  printf 'Notice: suspicious zero-usage frame; preserving previous snapshot\n' >&2
else
  cqg_write_snapshot "$five_int" "$seven_int" "$five_proj" "$five_reset" "$seven_reset" "$ctx_int" \
    "$agents_running" "$todos_pending" "$session_id" || {
    printf 'Warning: Failed to write quota snapshot\n' >&2
  }

  # Optional JSON export for other tools (no-op unless CQG_EXPORT_JSON set).
  # Passes raw reset epochs (not the human "3d"/"4h" deltas) so consumers get
  # machine-readable timestamps. Non-fatal: never break the status line.
  cqg_write_export_json "$five_int" "$seven_int" "$ctx_int" "$five_reset_at" "$seven_reset_at" || true
fi

# ── amortized cleanup of abandoned per-session snapshot/stamp files ─────
# Fires on ~1% of writes (CQG_SWEEP_RATE); deletes files older than N days.
# Non-fatal: cleanup must never break the status line.
cqg_sweep_stale || true

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

  # Extract provider domain from .claude/settings.local.json if present
  if command -v jq >/dev/null 2>&1; then
    cwd="$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)"
    if [[ -n "$cwd" ]]; then
      settings_local="${cwd}/.claude/settings.local.json"
      if [[ -f "$settings_local" ]]; then
        base_url="$(jq -r '.env.ANTHROPIC_BASE_URL // empty' "$settings_local" 2>/dev/null)"
        if [[ -n "$base_url" && "$base_url" != "https://api.anthropic.com"* ]]; then
          provider_domain="$(printf '%s' "$base_url" | sed -E 's|^https?://([^/:]+).*|\1|')"
          [[ -n "$provider_domain" ]] && line="${line:+$line · }${provider_domain}"
        fi
      fi
    fi
  fi

  printf '%s\n' "$line"
fi
