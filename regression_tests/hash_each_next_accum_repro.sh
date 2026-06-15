#!/usr/bin/env bash
# Regression test for the Hash#each + `next` loop-carried accumulation drop.
#
# Hash#each is lowered by `lower_hash_each_dynamic`. Unlike the other intrinsic
# loops (times/upto/downto/range/Array#each) it used to push the *cond* phis onto
# @loop_phi_stack and build a separate merge-phi in the increment block only AFTER
# the body was lowered. `lower_next` therefore patched the cond phi with a phantom
# incoming from the `next`-block (whose real successor is incr_block, NOT cond_block),
# while the increment-block merge-phi got no `next`-path incoming at all — so a `next`
# silently froze the accumulator (e.g. {1=>10,2=>20,3=>30}.each{ next if k==2; s+=v }
# returned 30 instead of 40).
#
# Fix: Hash#each now uses the same two-phi scheme as the rest of the family. The
# increment-merge phis are pre-created before the body and pushed onto @loop_phi_stack,
# so `lower_next` wires its value into the phi that actually lives in incr_block. The
# incr-phi then merges the body fall-through edge, the deleted-entry skip edge, and any
# `next` edges; an unconditional `next` (dead fall-through) wires the unchanged
# loop-head value via the control_flow_dead_block? guard.
#
# NOTE — still out of scope (separate root cause): nested inline-yield + `next` forces
# closure proc materialization, which routes the accumulator through the broken global
# closure-cell mechanism. Not asserted here.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hashnext_accum.XXXXXX")"
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
# Conditional next: skip exactly one iteration (key-based)
s1 = 0
{1 => 10, 2 => 20, 3 => 30}.each do |k, v|
  next if k == 2
  s1 = s1 + v            # 10 + 30 = 40
end

# Conditional next: skip the LAST iteration (exit-path edge)
s2 = 0
{1 => 10, 2 => 20, 3 => 30}.each do |k, v|
  next if k == 3
  s2 = s2 + v            # 10 + 20 = 30
end

# Conditional next: value-based predicate
s3 = 0
{1 => 10, 2 => 20, 3 => 30}.each do |k, v|
  next if v >= 20
  s3 = s3 + v            # 10
end

# Unconditional next: body fall-through dead -> accumulator stays at init
s4 = 0
{1 => 10, 2 => 20, 3 => 30}.each do |k, v|
  next
  s4 = s4 + v            # dead; s4 stays 0
end

# Unconditional next with nonzero init -> init preserved (not garbage)
s5 = 7
{1 => 10, 2 => 20, 3 => 30}.each do |k, v|
  next
  s5 = s5 + v            # dead; s5 stays 7
end

# No-next baseline (must remain correct)
s6 = 0
{1 => 10, 2 => 20, 3 => 30}.each do |k, v|
  s6 = s6 + v            # 60
end

# Two accumulators in one block + conditional next
a1 = 0
a2 = 0
{1 => 10, 2 => 20, 3 => 30, 4 => 40}.each do |k, v|
  next if k == 2
  a1 = a1 + v            # 10 + 30 + 40 = 80
  a2 = a2 + 1            # 3 (k=1,3,4)
end

# break + next in the same loop (break_info exit-phi path)
b = 0
{1 => 10, 2 => 20, 3 => 30, 4 => 40}.each do |k, v|
  next if k == 1         # skip 10
  break if k == 4        # stop before 40
  b = b + v              # 20 + 30 = 50
end

# Deleted-entry skip path interacting with next
# (exercises all three incr_block predecessors: skip, body, next)
hd = {1 => 10, 2 => 20, 3 => 30, 4 => 40}
hd.delete(2)
d = 0
hd.each do |k, v|
  next if k == 3
  d = d + v              # 10 + 40 = 50
end

# Empty hash + next (no iterations)
e = 5
empty = {} of Int32 => Int32
empty.each do |k, v|
  next
  e = e + v
end

STDERR.puts "S: #{s1} #{s2} #{s3} #{s4} #{s5} #{s6}"
STDERR.puts "A: #{a1} #{a2}"
STDERR.puts "B: #{b}"
STDERR.puts "D: #{d}"
STDERR.puts "E: #{e}"
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

expected="S: 40 30 10 0 7 60
A: 80 3
B: 50
D: 50
E: 5"

if [[ "$stderr_text" == "$expected" ]]; then
  echo "fixed: Hash#each + next accumulation threaded correctly"
  exit 0
fi

echo "unexpected output (expected:"
printf '%s\n' "$expected"
echo ")"
cat "$RUN_OUT"
exit 1
