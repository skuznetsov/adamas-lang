#!/usr/bin/env bash
# Regression test for the Array#each_with_index loop-carried accumulation drop.
#
# Before fix: lower_array_each_with_index_dynamic (ast_to_hir.cr) wired the
# loop-carried-var back-edge from `resolve_loop_updated_value` -> ctx.lookup_local
# evaluated AFTER ctx.pop_scope. Post-pop, the lookup resolves the var back to the
# loop-header phi itself, producing a self-referential back-edge
# (`phi = [entry: init, incr: phi]`). The accumulator therefore never advanced:
# `total += x` inside an each_with_index block was silently dropped (stayed at its
# initial value). This is the exact shape used by parser.cr parse_def_receiver_name
# (sum of part sizes), where total computed as 0 -> Bytes.new(0) under-allocation ->
# heap overflow in s2b.
#
# Fix: mirror lower_array_each_intrinsic (the proven-correct Array#each sibling) -
# snapshot the body's updated values BEFORE pop_scope via
# snapshot_block_scope_phi_values, materialize a separate incr phi per var in the
# increment block, and wire: incr_phi <- body-exit value; header_phi <- incr_phi.
# This also fixes a latent `next` bug (the one-phi scheme pushed the header phi onto
# @loop_phi_stack, so `next` added an incoming from a non-predecessor block).
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ewi_accum.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
COMPILE_OUT="$TMP_DIR/compile.out"
COMPILE_ERR="$TMP_DIR/compile.err"
RUN_OUT="$TMP_DIR/run.out"

cleanup() {
  if [[ "$KEEP_TMP" != "1" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

cat >"$SRC" <<'CR'
# c1: plain each_with_index accumulation (no conditional)
a1 = [10, 20, 30]
c1 = 0
a1.each_with_index do |x, idx|
  c1 += x
end

# c2: each_with_index with the conditional statement-modifier (parser shape)
a2 = [10, 20, 30]
c2 = 0
a2.each_with_index do |x, idx|
  c2 += 2 if idx > 0
  c2 += x
end

# c3: exact parse_def_receiver_name form - sum Slice(UInt8) sizes + separators
parts = [] of Slice(UInt8)
parts << "foo".to_slice
parts << "barbaz".to_slice
c3 = 0
parts.each_with_index do |part, idx|
  c3 += 2 if idx > 0
  c3 += part.size
end

# c4: nested inline-yield accumulation - the each_with_index block is just
# `yield x, i` and the *caller* block does the `+=`. The accumulator update
# happens in a child scope and only propagates after pop_scope, so the back-edge
# must use the post-pop lookup; otherwise it self-references and stays at 0.
def ewi_yield
  [10, 11, 12].each_with_index do |x, i|
    yield x, i
  end
end
c4 = 0
c5 = 0
ewi_yield do |x, i|
  c4 += 1
  c5 += i
end

STDERR.puts "c1=#{c1} c2=#{c2} c3=#{c3} c4=#{c4} c5=#{c5}"
STDERR.flush
CR

set +e
"$COMPILER" "$SRC" -o "$BIN" >"$COMPILE_OUT" 2>"$COMPILE_ERR"
compile_status=$?
set -e

if [[ $compile_status -ne 0 ]]; then
  echo "compile failed"
  echo "compiler: $COMPILER"
  echo "status: $compile_status"
  echo "tmp_dir: $TMP_DIR"
  echo "--- stderr ---"
  cat "$COMPILE_ERR"
  echo "--- stdout ---"
  cat "$COMPILE_OUT"
  exit 2
fi

./scripts/run_safe.sh "$BIN" 5 256 >"$RUN_OUT"
stderr_text="$(awk '/^=== STDERR ===/{flag=1;next}/^\[EXIT/{flag=0}flag' "$RUN_OUT" | tr -d '\r' | sed '/^$/d')"

echo "compiler: $COMPILER"
echo "tmp_dir: $TMP_DIR"
echo "stderr:"
printf '%s\n' "$stderr_text"

# c1 = 10+20+30 = 60
# c2 = 10 + (2+20) + (2+30) = 64
# c3 = 3 + (2+6) = 11
# c4 = 1+1+1 = 3 (count of nested-yield iterations)
# c5 = 0+1+2 = 3 (sum of indices via nested yield)
expected="c1=60 c2=64 c3=11 c4=3 c5=3"

if [[ "$stderr_text" == "$expected" ]]; then
  echo "fixed: each_with_index loop-carried accumulation threaded correctly"
  exit 0
fi

echo "unexpected output (expected: $expected)"
cat "$RUN_OUT"
exit 1
