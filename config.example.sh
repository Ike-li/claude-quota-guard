# claude-quota-guard configuration
#
# Sourced by both collect.sh and guard.sh. Override any value via environment
# variables, or edit this file directly. Copy to config.sh during install.

# ── Thresholds (percent) ───────────────────────────────────────────────
# Context window usage that triggers a one-time NOTICE (advice only).
: "${CQG_CTX_NOTICE:=50}"
# Context window usage that triggers CONVERGENCE (write handoff, stop work).
: "${CQG_CTX_HALT:=85}"
# 5-hour rate-limit usage that triggers convergence (subscription only).
: "${CQG_RATE_HALT:=85}"

# ── Language for injected signals: en | zh ─────────────────────────────
: "${CQG_LANG:=en}"

# ── Data freshness: snapshots older than this many seconds are ignored ──
: "${CQG_MAX_AGE:=60}"

# ── File locations (rarely need changing) ──────────────────────────────
: "${CQG_SNAPSHOT:=$HOME/.claude/.quota-now}"
: "${CQG_NOTICE_STAMP:=$HOME/.claude/.cqg-notice-stamp}"

# ── Wrapped status line (set by installer in wrap mode) ────────────────
# If set, collect.sh forwards stdin to this command and prints its output,
# so your existing status line keeps working. Empty = standalone mode.
: "${CQG_WRAPPED_STATUSLINE:=}"
