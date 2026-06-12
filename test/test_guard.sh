#!/usr/bin/env bash
# claude-quota-guard :: test_guard.sh
# Self-contained regression for guard.sh. Uses a temp snapshot + isolated
# config; never touches the user's real ~/.claude files.

set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$SELF_DIR/../hooks/guard.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SNAP="$TMP/snap"; STAMP="$TMP/stamp"; CFG="$TMP/config.sh"

cat > "$CFG" <<EOF
CQG_CTX_NOTICE=50
CQG_CTX_HALT=85
CQG_RATE_HALT=85
CQG_LANG=en
CQG_MAX_AGE=60
CQG_SNAPSHOT="$SNAP"
CQG_NOTICE_STAMP="$STAMP"
EOF

pass=0; fail=0
# snap <fields...> : write tab-joined snapshot, fresh mtime
snap() { local IFS=$'\t'; printf '%s\n' "$*" > "$SNAP"; }
# run <mode> : run guard with given CQG_MODE (default auto)
run() { CQG_CONFIG="$CFG" CQG_MODE="${1:-auto}" bash "$GUARD" </dev/null; }
# expect <desc> <needle|EMPTY> <output>
expect() {
  local desc="$1" needle="$2" out="$3"
  if [[ "$needle" == "EMPTY" ]]; then
    if [[ -z "$out" ]]; then echo "  ✓ $desc"; ((pass++)); else echo "  ✗ $desc — expected empty, got: $out"; ((fail++)); fi
  else
    if [[ "$out" == *"$needle"* ]]; then echo "  ✓ $desc"; ((pass++)); else echo "  ✗ $desc — missing '$needle' in: $out"; ((fail++)); fi
  fi
}

echo "== tier + mode matrix =="
rm -f "$STAMP"; snap 40 9 45 2h 5d 30
expect "sub: ctx30/5h40 → silent" EMPTY "$(run)"

rm -f "$STAMP"; snap 92 9 110 1h 5d 30
expect "sub: 5h92 → QUOTA-LOW" "QUOTA-LOW" "$(run subscription)"
expect "sub: 5h92 shows 5h line" "5h usage: 92%" "$(run subscription)"

rm -f "$STAMP"; snap 17 12 164 4h 5d 20
expect "sub: 5h17 + proj164 → silent (proj not a trigger)" EMPTY "$(run subscription)"

rm -f "$STAMP"; snap 40 9 45 2h 5d 88
expect "sub: ctx88 → QUOTA-LOW" "QUOTA-LOW" "$(run)"

rm -f "$STAMP"; snap '' '' '' '' '' 90
expect "relay: ctx90 (empty 5h) → QUOTA-LOW" "QUOTA-LOW" "$(run relay)"

rm -f "$STAMP"; snap 99 99 150 1h 5d 20
expect "relay: fake 5h99/ctx20 → silent (rate ignored)" EMPTY "$(run relay)"

echo "== notice tier + dedup =="
rm -f "$STAMP"; snap 0 0 0 - - 60
expect "ctx60 first → CTX-NOTICE" "CTX-NOTICE" "$(run)"
expect "ctx60 again → silent (dedup)" EMPTY "$(run)"

snap 0 0 0 - - 30
expect "ctx30 → silent (clears stamp)" EMPTY "$(run)"
snap 0 0 0 - - 60
expect "ctx60 re-cross → CTX-NOTICE again" "CTX-NOTICE" "$(run)"

echo "== freshness =="
rm -f "$STAMP"; snap 0 0 0 - - 90
touch -t 200001010000 "$SNAP"
expect "stale snapshot → silent" EMPTY "$(run)"

echo "== per-session snapshot precedence =="
rm -f "$STAMP" "${STAMP}-S1"
snap 0 0 0 - - 30                                  # global: ctx 30 (would be silent)
printf '0\t0\t0\t-\t-\t90\n' > "${SNAP}-S1"        # session S1: ctx 90 (would converge)
out="$(CQG_CONFIG="$CFG" bash "$GUARD" <<< '{"session_id":"S1"}')"
expect "guard prefers per-session (ctx90) over global (ctx30)" "QUOTA-LOW" "$out"
rm -f "${SNAP}-S1" "${STAMP}-S1"

echo "== session_id present but no per-session file → no global fallback (cross-talk guard) =="
# Regression: every session writes the shared global file, so a session reading
# global inherits another session's numbers. With a session_id, guard must read
# ONLY its own file; if absent, stay silent rather than cross-talk.
rm -f "$STAMP"; snap 98 10 18 now 5d 6             # global: someone else's 5h=98 (would converge)
expect "sess present + per-session missing → silent (ignores global 5h=98)" \
  EMPTY "$(CQG_CONFIG="$CFG" bash "$GUARD" <<< '{"session_id":"GHOST"}')"
# Sanity: the very same global snapshot DOES trigger when there is no session_id.
rm -f "$STAMP"
expect "no session_id + global 5h=98 → QUOTA-LOW (global still used)" \
  "QUOTA-LOW" "$(CQG_CONFIG="$CFG" bash "$GUARD" </dev/null)"

echo "== collect writes per-session snapshot =="
COLLECT="$SELF_DIR/../hooks/collect.sh"
csnap="$TMP/csnap"
echo '{"context_window":{"used_percentage":77},"session_id":"CS1"}' \
  | CQG_SNAPSHOT="$csnap" CQG_WRAPPED_STATUSLINE="" bash "$COLLECT" >/dev/null 2>&1
if [[ -f "${csnap}-CS1" ]]; then echo "  ✓ collect wrote per-session file (.quota-now-CS1)"; ((pass++)); else echo "  ✗ collect missing per-session file"; ((fail++)); fi

echo "== i18n =="
rm -f "$STAMP"; snap 40 9 45 2h 5d 88
CFG_ZH="$TMP/config.zh.sh"; sed 's/CQG_LANG=en/CQG_LANG=zh/' "$CFG" > "$CFG_ZH"
out="$(CQG_CONFIG="$CFG_ZH" bash "$GUARD" </dev/null)"
expect "zh: ctx88 → 收敛协议" "收敛协议" "$out"

echo "== configurable threshold =="
rm -f "$STAMP"; snap 0 0 0 - - 70
CFG_T="$TMP/config.t.sh"; sed 's/CQG_CTX_HALT=85/CQG_CTX_HALT=65/' "$CFG" > "$CFG_T"
out="$(CQG_CONFIG="$CFG_T" bash "$GUARD" </dev/null)"
expect "ctx70 with HALT=65 → QUOTA-LOW" "QUOTA-LOW" "$out"

echo "== auto-detection from snapshot data =="
rm -f "$STAMP"; snap '' '' '' '' '' 30
expect "auto: empty 5h field → relay-like (rate skipped, ctx check only)" EMPTY "$(run auto)"

rm -f "$STAMP"; snap 99 0 150 1h - 20
expect "auto: 5h=99 ctx=20 → rate active, 99>=85 → QUOTA-LOW" "QUOTA-LOW" "$(run auto)"

rm -f "$STAMP"; snap 40 0 45 2h - 30
expect "auto: 5h=40 → rate active, 40<85 → silent" EMPTY "$(run auto)"

echo ""
echo "Result: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
