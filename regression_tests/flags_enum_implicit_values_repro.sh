#!/usr/bin/env bash
# @[Flags] enum implicit member values must follow original Crystal semantics:
# first implicit member = 1, each next implicit member = previous * 2
# (semantic/top_level_visitor.cr visit_enum_member). Pre-fix our register_enum
# used the plain 0,1,2,... counter for every enum, so Regex::MatchOptions::ANCHORED
# was 0 and `options | ANCHORED` became a no-op (regex anchoring silently lost).
#
# RED  (pre-fix): prints 0/1/2 for MyF and 0 for ANCHORED
# GREEN (post-fix): 1/2/4, ANCHORED=1, explicit-value reset honored (8, then 16)
set -u

COMPILER="${1:-bin/adamas}"
TMP_DIR="$(mktemp -d /tmp/flags_enum_repro.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/flags_enum.cr"
BIN="$TMP_DIR/flags_enum"

cat > "$SRC" <<'EOF'
@[Flags]
enum MyF
  A
  B
  C
  D = 8
  E
end

enum Plain
  X
  Y
  Z
end

puts MyF::A.value
puts MyF::B.value
puts MyF::C.value
puts MyF::D.value
puts MyF::E.value
puts Plain::X.value
puts Plain::Y.value
puts Plain::Z.value
puts Regex::MatchOptions::ANCHORED.value
puts Regex::MatchOptions::ENDANCHORED.value
EOF

"$COMPILER" "$SRC" -o "$BIN" >/dev/null 2>&1 || { echo "FAIL: compile error"; exit 1; }

ACTUAL="$("$BIN" 2>/dev/null)"
EXPECTED="1
2
4
8
16
0
1
2
1
2"

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  echo "PASS: @[Flags] implicit values are 1, prev*2 (plain enums unchanged)"
  exit 0
else
  echo "FAIL: unexpected enum values"
  echo "--- expected ---"; echo "$EXPECTED"
  echo "--- actual ---"; echo "$ACTUAL"
  exit 1
fi
