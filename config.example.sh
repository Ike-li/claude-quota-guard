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

# ── Rate-tier mode: auto | subscription | relay ────────────────────────
# auto:         detect from snapshot data (5h field non-empty = subscription).
#               Fixes the case where ANTHROPIC_BASE_URL leaks from the shell.
# subscription: always enable rate-limit tier (force 5h/7d checks).
# relay:        always skip rate-limit tier (API / relay, no budget concept).
: "${CQG_MODE:=auto}"

# ── Data freshness: snapshots older than this many seconds are ignored ──
: "${CQG_MAX_AGE:=60}"

# ── File locations (rarely need changing) ──────────────────────────────
: "${CQG_SNAPSHOT:=$HOME/.claude/.quota-now}"
: "${CQG_NOTICE_STAMP:=$HOME/.claude/.cqg-notice-stamp}"

# ── Wrapped status line (set by installer in wrap mode) ────────────────
# If set, collect.sh forwards stdin to this command and prints its output,
# so your existing status line keeps working. Empty = standalone mode.
# The installer writes this dynamically, loading from .cqg-wrap.json to avoid
# shell metacharacter escaping issues. Manual override: set CQG_WRAPPED_STATUSLINE
# in your environment or uncomment and edit the line below.
# : "${CQG_WRAPPED_STATUSLINE:=}"
