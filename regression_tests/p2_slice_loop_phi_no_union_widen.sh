#!/bin/bash
# Regression: HIR `collect_local_assignment_types` BinaryNode case used to infer
# a phi variable's type from the OTHER operand of any binary expression.
# For `peek += avail` where peek is Slice and avail is Int, this widened the
# loop phi to a fake `Int32 | Slice` union → vdispatch on .size selected
# `Int32#size` (a STUB CALLED abort) at runtime.
#
# Repro: gen_test below uses `peek += avail` and `limit -= avail` on a Slice
# parameter inside a while loop. Before the fix: STUB CALLED: Int32$Hsize
# (abort). After the fix: prints "6" (10 - 4).

set -e

COMPILER="${1:-bin/crystal_v2}"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

cat > "$TMP/repro.cr" <<'EOF'
def gen_test(peek, limit)
  while peek.size > 0 && limit > 0
    available = limit < peek.size ? limit : peek.size
    peek += available
    limit -= available
  end
  limit
end

slice = Slice(UInt8).new(4) { |i| i.to_u8 }
puts gen_test(slice, 10)
EOF

"$COMPILER" "$TMP/repro.cr" -o "$TMP/repro" >/dev/null 2>&1

OUT=$("$TMP/repro" 2>&1)
EXPECTED="6"

if [ "$OUT" = "$EXPECTED" ]; then
  echo "PASS: slice loop phi not widened to union"
  exit 0
else
  echo "FAIL: expected '$EXPECTED', got '$OUT'"
  exit 1
fi
