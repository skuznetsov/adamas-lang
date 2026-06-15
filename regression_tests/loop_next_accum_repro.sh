#!/usr/bin/env bash
# Regression test for the `next`-in-loop loop-carried accumulation drop in the
# intrinsic two-phi loop lowerings (times, upto/downto, range#each, Array#each
# static + dynamic).
#
# Two distinct defects, both fixed in the same commit:
#
#  1) CONDITIONAL `next` (e.g. `next if i == 2`): for upto/downto the loop exits
#     via the increment block, and the exit phi used to reference the
#     fall-through-only accumulator value (`u += i`). That value is undef in SSA
#     when the last iteration took the `next` path, so the backend read 0 and the
#     accumulator collapsed to its initial value. Fix: the exit phi now references
#     the increment-phi (which already merges the fall-through AND `next` edges).
#
#  2) UNCONDITIONAL `next` (`next` with dead code after it, or every body path
#     taking `next`): the body fall-through block is unreachable. Its accumulator
#     value is undef, but it was still wired as the incr-phi's body-exit incoming,
#     so the backend read garbage (a nonzero junk value instead of the unchanged
#     accumulator). Fix: on a control-flow-dead body-exit edge wire the header phi
#     (the loop-head value, i.e. "accumulator never advanced") instead.
#
# NOTE — out of scope for this reducer (separate root causes, tracked separately):
#   * Hash#each + `next` — different phi topology in lower_hash_each_dynamic.
#     NOW FIXED in a follow-up commit; asserted by hash_each_next_accum_repro.sh.
#   * Nested inline-yield + `next` — forces closure proc materialization, which
#     routes the accumulator through the broken global closure-cell mechanism.
#     Still broken; intentionally NOT asserted here.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/loopnext_accum.XXXXXX")"
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
# ---- CONDITIONAL next: skip exactly one iteration ----
c1 = 0
4.times do |i|
  next if i == 2
  c1 = c1 + i            # 0 + 1 + 3 = 4
end

c2 = 0
1.upto(5) do |i|
  next if i == 2
  c2 = c2 + i            # 1 + 3 + 4 + 5 = 13
end

c3 = 0
5.downto(1) do |i|
  next if i == 2
  c3 = c3 + i            # 5 + 4 + 3 + 1 = 13
end

c4 = 0
(1..5).each do |i|
  next if i == 2
  c4 = c4 + i            # 13
end

c5 = 0
[10, 20, 30].each do |x|
  next if x == 20
  c5 = c5 + x            # 10 + 30 = 40
end

arr6 = [10, 20, 30]
c6 = 0
arr6.each do |x|
  next if x == 20
  c6 = c6 + x            # 40
end

# ---- UNCONDITIONAL next: body fall-through is dead -> accumulator stays at init ----
u1 = 0
3.times do |i|
  next
  u1 = u1 + i            # dead; u1 stays 0
end

u2 = 0
1.upto(5) do |i|
  next
  u2 = u2 + i            # dead; u2 stays 0
end

u3 = 7
5.downto(1) do |i|
  next
  u3 = u3 + i            # dead; u3 stays 7 (init preserved, not garbage)
end

STDERR.puts "C: #{c1} #{c2} #{c3} #{c4} #{c5} #{c6}"
STDERR.puts "U: #{u1} #{u2} #{u3}"
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

expected="C: 4 13 13 13 40 40
U: 0 0 7"

if [[ "$stderr_text" == "$expected" ]]; then
  echo "fixed: next-in-loop accumulation threaded correctly (two-phi intrinsic loops)"
  exit 0
fi

echo "unexpected output (expected:"
printf '%s\n' "$expected"
echo ")"
cat "$RUN_OUT"
exit 1
