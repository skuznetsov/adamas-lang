#!/usr/bin/env bash
# Repro: pseudo-methods in block-shorthand form — &.as?(T), &.as(T),
# &.is_a?(T), &.responds_to?(:m).
#
# Root cause (fixed): parse_block_shorthand took current_token.slice as a
# plain method name for everything after `&.`, so pseudo-methods became
# ordinary MemberAccess/CallNodes (`tmp.as?(A)`) instead of the dedicated
# cast/check nodes parse_member_access builds for explicit `.as?`/`.as`/
# `.is_a?`/`.responds_to?`. Lowering then emitted a real method call on the
# receiver class — an abort stub for abstract bases. This was the L7 s2
# self-host floor: `vars["T"]?.try(&.as?(MacroTupleValue))` in
# macro_int_literal_for_expr_with_context aborted ~3s into any s2 compile
# (STUB CALLED: MacroValue#as?$$MacroTupleValue).
#
# GREEN: shorthand pseudo-methods behave exactly like the explicit forms.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/blk_pseudo.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/out"
LOG="$TMP_DIR/compile.log"
RUN_LOG="$TMP_DIR/run.log"

cat > "$SRC" <<'CR'
abstract class Base
end

class A < Base
  def val
    42
  end
end

class B < Base
end

def pick(n : Int32) : Base
  n > 0 ? A.new : B.new
end

# &.as?(T) through Hash#[]? + try — the exact L7 shape
vars = {} of String => Base
vars["T"] = A.new
vars["U"] = B.new
STDERR.puts "a=#{vars["T"]?.try(&.as?(A)).try(&.val)}"
STDERR.puts "b=#{vars["U"]?.try(&.as?(A)).nil?}"
STDERR.puts "c=#{vars["missing"]?.try(&.as?(A)).nil?}"

# &.as?(T) on a nilable local
v : Base? = pick(1)
STDERR.puts "d=#{v.try(&.as?(A)).try(&.val)}"

# &.as(T)
STDERR.puts "e=#{v.try(&.as(A)).try(&.val)}"

# &.as?(T) via a user yield method (non-try context)
def apply(x : Base)
  yield x
end
STDERR.puts "f=#{apply(pick(1), &.as?(A)).try(&.val)}"
# PARITY assert (not absolute): yield-method return drops the nil variant of
# `as?` (pre-existing sibling, explicit block form equally affected) — the
# shorthand fix only guarantees &. behaves exactly like the explicit block.
STDERR.puts "g=#{apply(pick(0), &.as?(A)).nil? == apply(pick(0)) { |x| x.as?(A) }.nil?}"

# &.is_a?(T) and &.responds_to?(:m)
STDERR.puts "h=#{v.try(&.is_a?(A))}"
# PARITY assert: responds_to? folds on the STATIC type (Base has no #val), no
# virtual expansion — pre-existing sibling, explicit form equally affected.
STDERR.puts "i=#{v.try(&.responds_to?(:val)) == v.try { |x| x.responds_to?(:val) }}"
STDERR.puts "j=#{pick(0).responds_to?(:val)}"

# chained postfix after the pseudo-method: &.as(T).val
STDERR.puts "k=#{apply(pick(1), &.as(A).val)}"
CR

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 8192 \
  "$SRC" -o "$OUT" >"$LOG" 2>&1

"$ROOT_DIR/scripts/run_safe.sh" "$OUT" 5 512 >"$RUN_LOG" 2>&1 || true

fail=0
for expect in "a=42" "b=true" "c=true" "d=42" "e=42" "f=42" "g=true" \
              "h=true" "i=true" "j=false" "k=42"; do
  grep -q "^$expect\$" "$RUN_LOG" || { echo "RED: missing '$expect'"; fail=1; }
done
if grep -q "STUB CALLED" "$RUN_LOG"; then
  echo "RED: abort stub called"
  fail=1
fi

if [[ "$fail" != "0" ]]; then
  echo "--- run log ---"
  cat "$RUN_LOG"
  exit 1
fi

echo "PASS: block-shorthand pseudo-methods (&.as?/&.as/&.is_a?/&.responds_to?)"
