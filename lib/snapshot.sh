#!/usr/bin/env bash
# claude-quota-guard :: lib/snapshot.sh
# Shared logic for writing quota snapshots. Sourced by collect.sh and
# statusline-command.sh to ensure per-session snapshot handling stays consistent.

# Anthropic's 5-hour rate-limit window in seconds (5 * 3600 = 18000).
# If Anthropic changes the window size, update here only.
readonly CQG_FIVE_HOUR_WINDOW=18000

# Sanitize session_id for safe use in filenames.
# Input: raw session_id string from JSON
# Output: cleaned string (only alphanumerics, dots, dashes, underscores)
cqg_sanitize_session_id() {
  printf '%s' "$1" | tr -cd 'A-Za-z0-9_.-'
}

# Write a snapshot atomically (both global and per-session if session_id provided).
# Args: five_int seven_int five_proj five_reset seven_reset ctx_int session_id
# Env:  CQG_SNAPSHOT (base path, e.g., ~/.claude/.quota-now)
cqg_write_snapshot() {
  local five_int="$1" seven_int="$2" five_proj="$3"
  local five_reset="$4" seven_reset="$5" ctx_int="$6"
  local session_id="$7"

  local snap_line
  snap_line="$(printf '%s\t%s\t%s\t%s\t%s\t%s' \
    "$five_int" "$seven_int" "$five_proj" "$five_reset" "$seven_reset" "$ctx_int")"

  _cqg_write_file() {
    local dest="$1" tmp
    tmp="$(mktemp "${dest}.XXXXXX" 2>/dev/null || echo "${dest}.tmp")"
    printf '%s\n' "$snap_line" > "$tmp"
    mv -f "$tmp" "$dest"
  }

  # Always write global snapshot
  _cqg_write_file "${CQG_SNAPSHOT}"

  # Write per-session snapshot if session_id provided
  if [[ -n "$session_id" ]]; then
    _cqg_write_file "${CQG_SNAPSHOT}-${session_id}"
  fi
}
