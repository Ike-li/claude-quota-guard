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
CQG_RATE_PROJ_HALT=150
CQG_LANG=en
CQG_MAX_AGE=60
CQG_SNAPSHOT="$SNAP"
CQG_NOTICE_STAMP="$STAMP"
EOF

pass=0; fail=0
# snap <fields...> : write tab-joined snapshot, fresh mtime
snap() { local IFS=$'\t'; printf '%s\n' "$*" > "$SNAP"; }
# run <base_url> : run guard with given config, capture stdout
run() { CQG_CONFIG="$CFG" ANTHROPIC_BASE_URL="$1" bash "$GUARD" </dev/null; }
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
expect "sub: ctx30/5h40 → silent" EMPTY "$(run '')"

rm -f "$STAMP"; snap 92 9 110 1h 5d 30
expect "sub: 5h92 → QUOTA-LOW" "QUOTA-LOW" "$(run '')"
expect "sub: 5h92 shows 5h line" "5h usage: 92%" "$(run '')"

rm -f "$STAMP"; snap 40 9 45 2h 5d 88
expect "sub: ctx88 → QUOTA-LOW" "QUOTA-LOW" "$(run '')"

rm -f "$STAMP"; snap '' '' '' '' '' 90
expect "relay: ctx90 (empty 5h) → QUOTA-LOW" "QUOTA-LOW" "$(run 'https://relay.example')"

rm -f "$STAMP"; snap 99 99 150 1h 5d 20
expect "relay: fake 5h99/ctx20 → silent (rate ignored)" EMPTY "$(run 'https://relay.example')"

echo "== notice tier + dedup =="
rm -f "$STAMP"; snap 0 0 0 - - 60
expect "ctx60 first → CTX-NOTICE" "CTX-NOTICE" "$(run '')"
expect "ctx60 again → silent (dedup)" EMPTY "$(run '')"

snap 0 0 0 - - 30
expect "ctx30 → silent (clears stamp)" EMPTY "$(run '')"
snap 0 0 0 - - 60
expect "ctx60 re-cross → CTX-NOTICE again" "CTX-NOTICE" "$(run '')"

echo "== freshness =="
rm -f "$STAMP"; snap 0 0 0 - - 90
touch -t 200001010000 "$SNAP"
expect "stale snapshot → silent" EMPTY "$(run '')"

echo "== i18n =="
rm -f "$STAMP"; snap 40 9 45 2h 5d 88
CFG_ZH="$TMP/config.zh.sh"; sed 's/CQG_LANG=en/CQG_LANG=zh/' "$CFG" > "$CFG_ZH"
out="$(CQG_CONFIG="$CFG_ZH" ANTHROPIC_BASE_URL='' bash "$GUARD" </dev/null)"
expect "zh: ctx88 → 收敛协议" "收敛协议" "$out"

echo "== configurable threshold =="
rm -f "$STAMP"; snap 0 0 0 - - 70
CFG_T="$TMP/config.t.sh"; sed 's/CQG_CTX_HALT=85/CQG_CTX_HALT=65/' "$CFG" > "$CFG_T"
out="$(CQG_CONFIG="$CFG_T" ANTHROPIC_BASE_URL='' bash "$GUARD" </dev/null)"
expect "ctx70 with HALT=65 → QUOTA-LOW" "QUOTA-LOW" "$out"

echo ""
echo "Result: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
