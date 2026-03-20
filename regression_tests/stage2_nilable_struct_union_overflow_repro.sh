#!/bin/bash
# Reproduction script: stage2 crashes because Nil|Struct unions are sized as
# 8-byte nullable pointers in HIR, but 12-byte tagged unions in LLVM codegen.
# This causes buffer overflow on the last field of classes with nilable struct ivars.
# 
# Usage: bash regression_tests/stage2_nilable_struct_union_overflow_repro.sh <compiler>
set -euo pipefail
COMPILER="${1:?Usage: $0 <compiler>}"

# Create a test with nilable struct field as LAST ivar (triggers overflow)
TMPFILE=$(mktemp /tmp/union_overflow_XXXXXX.cr)
trap "rm -f $TMPFILE /tmp/union_overflow_bin" EXIT

cat > "$TMPFILE" << 'EOF'
class TestNode
  getter name : Slice(UInt8)
  getter data : Array(Int32)?
  getter receiver : Slice(UInt8)?  # last field = nilable struct = overflow

  def initialize(@name, @data, @receiver)
  end
end

node = TestNode.new("hello".to_slice, [1,2,3], "world".to_slice)
puts node.receiver.try(&.size) == 5 ? "ok" : "FAIL"

node2 = TestNode.new("x".to_slice, nil, nil)
puts node2.receiver.nil? ? "ok" : "FAIL"
EOF

# Compile and run
"$COMPILER" "$TMPFILE" -o /tmp/union_overflow_bin 2>/dev/null
OUTPUT=$(scripts/run_safe.sh /tmp/union_overflow_bin 5 512 2>/dev/null)
if echo "$OUTPUT" | grep -q "ok"; then
  echo "not reproduced: nilable struct union layout is correct"
  exit 0
else
  echo "reproduced: nilable struct union overflow (exit or wrong output)"
  exit 1
fi
