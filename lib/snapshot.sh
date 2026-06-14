#!/usr/bin/env bash
# claude-quota-guard :: lib/snapshot.sh
# Shared logic for writing quota snapshots. Sourced by collect.sh and
# statusline-command.sh to ensure per-session snapshot handling stays consistent.

# Anthropic's 5-hour rate-limit window in seconds (5 * 3600 = 18000).
# If Anthropic changes the window size, update here only.
# shellcheck disable=SC2034  # used by scripts that source this file
# Idempotent: re-sourcing this lib in one `set -e` process must not abort on a
# "readonly variable" error (a plain `readonly X=` re-assignment returns non-zero
# → set -e exits). Still effectively const after the first source.
[[ -n "${CQG_FIVE_HOUR_WINDOW:-}" ]] || readonly CQG_FIVE_HOUR_WINDOW=18000

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
# Args: five_int seven_int five_proj five_reset seven_reset ctx_int agents_running todos_pending session_id
# Env:  CQG_SNAPSHOT (base path, e.g., ~/.claude/.quota-now)
# Returns: 0 on success, 1 on failure
cqg_write_snapshot() {
  local five_int="$1" seven_int="$2" five_proj="$3"
  local five_reset="$4" seven_reset="$5" ctx_int="$6"
  local agents_running="$7" todos_pending="$8" session_id="$9"

  # Validate all required fields are present (empty is ok, but must be 8 fields + optional session)
  if [[ $# -lt 8 ]]; then
    printf 'cqg_write_snapshot: insufficient arguments (got %d, need 8-9)\n' "$#" >&2
    return 1
  fi

  # Validate CQG_SNAPSHOT is set
  if [[ -z "${CQG_SNAPSHOT:-}" ]]; then
    printf 'cqg_write_snapshot: CQG_SNAPSHOT not set\n' >&2
    return 1
  fi

  local snap_line
  snap_line="$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
    "$five_int" "$seven_int" "$five_proj" "$five_reset" "$seven_reset" "$ctx_int" \
    "$agents_running" "$todos_pending")"

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

# ── JSON export bridge (opt-in) ─────────────────────────────────────────
# Writes the quota numbers as a standard JSON object so *other* tools can
# consume them (status bars, notifiers). Mirrors claude-hud's externalUsage
# export: single object, atomic write (tmp + mv), mode 0600.
#   - Disabled unless CQG_EXPORT_JSON points at a target path.
#   - Requires jq (used for safe JSON construction); silently no-ops without it.
#   - Empty fields are emitted as JSON null, never "".
#   - resets_at is unix epoch seconds (a consumer can treat values >1e12 as ms).
# Args: five_pct seven_pct ctx_pct five_reset_epoch seven_reset_epoch
# Env:  CQG_EXPORT_JSON (target path; empty/unset = disabled)
# Returns: 0 on success or when disabled, 1 on write failure.
cqg_write_export_json() {
  [[ -n "${CQG_EXPORT_JSON:-}" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  local five="$1" seven="$2" ctx="$3" five_reset="$4" seven_reset="$5"
  local dest="$CQG_EXPORT_JSON" tmp json now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # `nn`: empty string → null, numeric string → number, garbage → null.
  json="$(jq -cn \
    --arg now "$now" \
    --arg five "$five" --arg seven "$seven" --arg ctx "$ctx" \
    --arg fr "$five_reset" --arg sr "$seven_reset" '
      def nn: if . == "" then null else (tonumber? // null) end;
      {
        updated_at: $now,
        five_hour: { used_percentage: ($five|nn), resets_at: ($fr|nn) },
        seven_day: { used_percentage: ($seven|nn), resets_at: ($sr|nn) },
        context:   { used_percentage: ($ctx|nn) }
      }' 2>/dev/null)" || return 1
  [[ -n "$json" ]] || return 1

  tmp="$(mktemp "${dest}.XXXXXXXXXX" 2>/dev/null)" || {
    printf 'cqg_write_export_json: mktemp failed for %s\n' "$dest" >&2
    return 1
  }
  if ! printf '%s\n' "$json" > "$tmp" 2>/dev/null; then
    rm -f "$tmp" 2>/dev/null
    return 1
  fi
  chmod 600 "$tmp" 2>/dev/null || true
  if ! mv -f "$tmp" "$dest" 2>/dev/null; then
    rm -f "$tmp" 2>/dev/null
    return 1
  fi
}

# ── Stale per-session file sweep ────────────────────────────────────────
# Every session_id leaves a `${CQG_SNAPSHOT}-<id>` snapshot (and guard leaves a
# `${CQG_NOTICE_STAMP}-<id>` stamp). Nothing prunes them at runtime, so SDK child
# sessions and CI batches let them accumulate without bound. Mirrors claude-hud's
# context-cache sweep: a cheap, amortized cleanup that fires on only a fraction of
# writes (never on the hot path), deleting per-session files older than N days.
#
# Active sessions are safe: their files are rewritten every ~10s, so an mtime
# older than CQG_SWEEP_MAX_AGE_DAYS only ever matches abandoned sessions. The
# global `${CQG_SNAPSHOT}` / `${CQG_NOTICE_STAMP}` (no `-<id>` suffix) and the
# mktemp `.XXXX` temp files (dot, not dash) never match the `<base>-*` glob.
#
# Env: CQG_SWEEP_RATE (1-in-N chance; default 100 ≈ 1%, 0 disables)
#      CQG_SWEEP_MAX_AGE_DAYS (default 7)
#      CQG_SWEEP_FORCE=1 forces a run regardless of the dice (tests)
cqg_sweep_stale() {
  local rate="${CQG_SWEEP_RATE:-100}"
  local max_age="${CQG_SWEEP_MAX_AGE_DAYS:-7}"

  if [[ "${CQG_SWEEP_FORCE:-0}" != "1" ]]; then
    [[ "$rate" =~ ^[0-9]+$ && "$rate" -gt 0 ]] || return 0
    (( RANDOM % rate == 0 )) || return 0
  fi
  [[ "$max_age" =~ ^[0-9]+$ ]] || max_age=7

  _cqg_sweep_family() {
    local base="$1" dir name
    [[ -n "$base" ]] || return 0
    dir="$(dirname "$base")"; name="$(basename "$base")"
    [[ -d "$dir" ]] || return 0
    # -mtime +N matches files strictly older than N days; -maxdepth 1 keeps it
    # to this directory. Per-file/permission errors are swallowed.
    find "$dir" -maxdepth 1 -type f -name "${name}-*" -mtime "+${max_age}" -delete 2>/dev/null || true
  }

  _cqg_sweep_family "${CQG_SNAPSHOT:-}"
  _cqg_sweep_family "${CQG_NOTICE_STAMP:-}"
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
