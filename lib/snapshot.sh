#!/usr/bin/env bash
# claude-quota-guard :: lib/snapshot.sh
# Shared logic for writing quota snapshots. Sourced by collect.sh and
# statusline-command.sh to ensure per-session snapshot handling stays consistent.

# Anthropic's 5-hour rate-limit window in seconds (5 * 3600 = 18000).
# If Anthropic changes the window size, update here only.
# shellcheck disable=SC2034  # used by scripts that source this file
readonly CQG_FIVE_HOUR_WINDOW=18000

# Cached platform detection for stat command (Linux uses -c, BSD/macOS uses -f)
_CQG_STAT_PLATFORM=""
_cqg_detect_stat_platform() {
  if [[ -z "$_CQG_STAT_PLATFORM" ]]; then
    if stat -c %Y /dev/null >/dev/null 2>&1; then
      _CQG_STAT_PLATFORM="linux"
    else
      _CQG_STAT_PLATFORM="bsd"
    fi
  fi
}

# Get file modification time (cached platform detection)
cqg_stat_mtime() {
  local file="$1"
  _cqg_detect_stat_platform
  if [[ "$_CQG_STAT_PLATFORM" == "linux" ]]; then
    stat -c %Y "$file" 2>/dev/null || echo 0
  else
    stat -f %m "$file" 2>/dev/null || echo 0
  fi
}

# Get file size (cached platform detection)
cqg_stat_size() {
  local file="$1"
  _cqg_detect_stat_platform
  if [[ "$_CQG_STAT_PLATFORM" == "linux" ]]; then
    stat -c %s "$file" 2>/dev/null || echo 0
  else
    stat -f %z "$file" 2>/dev/null || echo 0
  fi
}

# Sanitize session_id for safe use in filenames.
# Input: raw session_id string from JSON
# Output: cleaned string (only alphanumerics, dots, dashes, underscores)
cqg_sanitize_session_id() {
  [[ -n "${1:-}" ]] || return 0
  printf '%s' "$1" | tr -cd 'A-Za-z0-9_.-'
}

# Write a snapshot atomically (both global and per-session if session_id provided).
# Args: five_int seven_int five_proj five_reset seven_reset ctx_int session_id
# Env:  CQG_SNAPSHOT (base path, e.g., ~/.claude/.quota-now)
# Returns: 0 on success, 1 on failure
cqg_write_snapshot() {
  local five_int="$1" seven_int="$2" five_proj="$3"
  local five_reset="$4" seven_reset="$5" ctx_int="$6"
  local session_id="$7"

  # Validate all required fields are present (empty is ok, but must be 6 fields)
  if [[ $# -lt 6 ]]; then
    printf 'cqg_write_snapshot: insufficient arguments (got %d, need 6-7)\n' "$#" >&2
    return 1
  fi

  # Validate CQG_SNAPSHOT is set
  if [[ -z "${CQG_SNAPSHOT:-}" ]]; then
    printf 'cqg_write_snapshot: CQG_SNAPSHOT not set\n' >&2
    return 1
  fi

  local snap_line
  snap_line="$(printf '%s\t%s\t%s\t%s\t%s\t%s' \
    "$five_int" "$seven_int" "$five_proj" "$five_reset" "$seven_reset" "$ctx_int")"

  _cqg_write_file() {
    local dest="$1" tmp
    # Use 10 X's for better entropy on busy systems
    tmp="$(mktemp "${dest}.XXXXXXXXXX" 2>/dev/null)" || {
      # If mktemp fails, fail loudly rather than attempting unsafe direct write
      printf 'cqg_write_snapshot: mktemp failed for %s\n' "$dest" >&2
      return 1
    }
    # Write to temp file
    if ! printf '%s\n' "$snap_line" > "$tmp" 2>/dev/null; then
      rm -f "$tmp" 2>/dev/null
      printf 'cqg_write_snapshot: write failed for %s\n' "$tmp" >&2
      return 1
    fi
    # Atomic move
    if ! mv -f "$tmp" "$dest" 2>/dev/null; then
      rm -f "$tmp" 2>/dev/null
      printf 'cqg_write_snapshot: mv failed for %s -> %s\n' "$tmp" "$dest" >&2
      return 1
    fi
  }

  # Write global snapshot
  _cqg_write_file "${CQG_SNAPSHOT}" || return 1

  # Write per-session snapshot if session_id provided
  if [[ -n "$session_id" ]]; then
    _cqg_write_file "${CQG_SNAPSHOT}-${session_id}" || return 1
  fi
}

# ── 5h burn-rate projection ─────────────────────────────────────────────
# Projects what % of the 5h budget we'll burn by the time the window resets,
# given current usage and elapsed time. Returns empty if there isn't enough
# data yet (<5 min elapsed) or inputs are missing/nonsensical.
# Args: used_pct reset_epoch [now_epoch]
cqg_five_hour_projection() {
  local used="$1" reset="$2" now="${3:-$(date +%s)}"
  [[ -n "$used" && -n "$reset" ]] || return 0
  awk -v used="$used" -v reset="$reset" -v now="$now" -v win="$CQG_FIVE_HOUR_WINDOW" 'BEGIN {
    remain = reset - now; elapsed = win - remain;
    if (elapsed <= 0 || elapsed < 300 || used <= 0) exit;
    p = used * win / elapsed; if (p > 999) p = 999;
    printf "%.0f", p;
  }'
}

# ── Human-readable reset countdown ──────────────────────────────────────
# Converts a future epoch into a compact label: "3d", "4h", "12m", "45s",
# "now" (if the epoch has passed), or empty for missing input.
# Args: epoch
cqg_fmt_reset_delta() {
  local epoch="$1" now
  [[ -n "$epoch" ]] || return 0
  now="$(date +%s)"
  awk -v e="$epoch" -v n="$now" 'BEGIN {
    s = e - n; if (s <= 0) { print "now"; exit }
    if (s >= 86400) printf "%dd", int(s/86400);
    else if (s >= 3600) printf "%dh", int(s/3600);
    else if (s >= 60) printf "%dm", int(s/60);
    else printf "%ds", s;
  }'
}
