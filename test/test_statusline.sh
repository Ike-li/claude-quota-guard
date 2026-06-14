#!/usr/bin/env bash
# claude-quota-guard :: test_statusline.sh
# Self-contained regression for statusline-command.sh color rendering.
#
# Themes (themes/*.sh) define colors as #RRGGBB hex; the status line must convert
# them to ANSI escapes honoring terminal color depth (truecolor → 256 → 16) and
# never print raw hex. Regression target: a loaded theme used to leak its hex
# literally (#d08770) because the variables were treated as ANSI escapes.
#
# Also guards the set -u leak from load-config.sh: an empty mode_parts array
# (session with no effort/thinking/fast) must not blank the whole line.
#
# Uses an isolated CLAUDE_CONFIG_DIR + temp snapshot; never touches real ~/.claude.

set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SL="$SELF_DIR/../statusline-command.sh"
ESC=$(printf '\033')

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# JSON with effort+thinking (non-empty mode_parts) and a bare variant (empty array)
JSON_FULL='{"model":{"display_name":"Opus 4.8"},"workspace":{"current_dir":"'"$TMP"'"},"effort":{"level":"max"},"thinking":{"enabled":true}}'
JSON_BARE='{"model":{"display_name":"Opus 4.8"},"workspace":{"current_dir":"'"$TMP"'"}}'

pass=0; fail=0

# render <theme> <preset> <COLORTERM> <TERM> <json> : run statusline fully isolated
render() {
  local cfg; cfg=$(mktemp -d "$TMP/cfg.XXXXXX")
  mkdir -p "$cfg/quota-guard"
  cat > "$cfg/quota-guard/settings.json" <<EOF
{"display":{"statusline":{"theme":"$1","preset":"$2","responsive":false}}}
EOF
  printf '%s' "$5" | CLAUDE_CONFIG_DIR="$cfg" COLORTERM="$3" TERM="$4" \
    CQG_SNAPSHOT="$cfg/.quota-now" bash "$SL" 2>&1
}

has()   { if [[ "$3" == *"$2"* ]]; then echo "  ✓ $1"; ((pass++)); else echo "  ✗ $1 — missing '$2'"; ((fail++)); fi; }
hasnt() { if [[ "$3" != *"$2"* ]]; then echo "  ✓ $1"; ((pass++)); else echo "  ✗ $1 — unexpected '$2'"; ((fail++)); fi; }
no_raw_hex() {
  local re='#[0-9a-fA-F]{6}'
  if [[ "$2" =~ $re ]]; then echo "  ✗ $1 — literal hex '${BASH_REMATCH[0]}' leaked"; ((fail++)); else echo "  ✓ $1"; ((pass++)); fi
}

echo "== themes render to ANSI, never raw hex (truecolor) =="
out="$(render nord compact truecolor xterm-256color "$JSON_FULL")"
no_raw_hex "nord: no literal hex in output" "$out"
has "nord: PEACH #d08770 → 38;2;208;135;112"   "${ESC}[38;2;208;135;112m" "$out"
has "nord: SAPPHIRE #5e81ac → 38;2;94;129;172" "${ESC}[38;2;94;129;172m"  "$out"

out="$(render catppuccin-mocha full truecolor xterm-256color "$JSON_FULL")"
no_raw_hex "catppuccin: no literal hex in output" "$out"
has "catppuccin: PEACH #fab387 → 38;2;250;179;135" "${ESC}[38;2;250;179;135m" "$out"

out="$(render cyberpunk full truecolor xterm-256color "$JSON_FULL")"
no_raw_hex "cyberpunk: no literal hex in output" "$out"
has "cyberpunk: PEACH #ffaa00 → 38;2;255;170;0" "${ESC}[38;2;255;170;0m" "$out"

echo "== color-depth downgrade applies to theme colors too =="
out="$(render nord compact "" xterm-256color "$JSON_FULL")"
no_raw_hex "256: no literal hex" "$out"
has   "256: PEACH #d08770 → cube idx 174" "${ESC}[38;5;174m" "$out"
hasnt "256: no truecolor escapes leak"    "${ESC}[38;2;"      "$out"

out="$(render nord compact "" xterm "$JSON_FULL")"
no_raw_hex "16: no literal hex" "$out"
has   "16: PEACH #d08770 → bright (93)"  "${ESC}[93m"    "$out"
hasnt "16: no 256 escapes leak"          "${ESC}[38;5;"  "$out"
hasnt "16: no truecolor escapes leak"    "${ESC}[38;2;"  "$out"

echo "== robustness: empty mode_parts must not crash (set -u leak from load-config) =="
out="$(render nord compact truecolor xterm-256color "$JSON_BARE")"
errre='unbound|: line [0-9]+:'
if [[ -n "$out" ]] && [[ ! "$out" =~ $errre ]]; then
  echo "  ✓ bare session (no effort/thinking) renders without crash"; ((pass++))
else
  echo "  ✗ bare session crashed or empty: $out"; ((fail++))
fi

echo ""
echo "Result: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
