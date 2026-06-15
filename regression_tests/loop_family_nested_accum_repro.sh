#!/usr/bin/env bash
# Regression test for the loop-family nested inline-yield accumulation drop.
#
# Sibling bug to array_each_with_index_accum_repro.sh. Seven intrinsic loop
# lowerings in ast_to_hir.cr (times, upto/downto, range#each, Array#each static,
# Array#each dynamic, Hash#each, plus each_with_index) wire the loop-carried-var
# back-edge from the PRE-POP `snapshot_block_scope_phi_values` value only. That
# snapshot is correct for the DIRECT case (`t += x` written in the loop block),
# but for the NESTED inline-yield case (the loop block is just `yield ...` and the
# *caller* block does the `+=`) the accumulator write lands in a child (yield)
# scope and only propagates to the enclosing scope AFTER pop_scope. So the pre-pop
# snapshot still resolves to the header phi -> the incr phi self-references the
# header phi -> the accumulator never advances (stays at its initial value).
#
# Fix: a shared `resolve_loop_backedge_value` helper used by all 7 back-patch
# sites: use the pre-pop snapshot when it advanced past the header phi (direct),
# else fall back to the post-pop `resolve_loop_updated_value` (nested). upto/downto
# additionally exit via the increment block (not the cond block), so their header
# phi is one iteration stale at exit; the inline caller-local is re-pointed at the
# exit phi so a nested accumulator picks up the final value, not the penultimate.
#
# NOTE: String#each_char nested (the 8th loop) is a SEPARATE, still-open root cause
# (its lowering builds no inline_vars phi for the accumulator) and is intentionally
# NOT asserted here. The DIRECT String#each_char case works and IS covered (d8).
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/loopfam_accum.XXXXXX")"
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
# ---- DIRECT accumulation (accumulator updated inside the loop block) ----
d1 = 0
3.times { |i| d1 += i }                       # 0+1+2 = 3

d2 = 0
1.upto(3) { |i| d2 += i }                      # 1+2+3 = 6

d3 = 0
3.downto(1) { |i| d3 += i }                    # 3+2+1 = 6

d4 = 0
(1..3).each { |i| d4 += i }                    # 6

d5 = 0
[10, 20, 30].each { |x| d5 += x }              # 60

arr6 = [10, 20, 30]
d6 = 0
arr6.each { |x| d6 += x }                      # 60

d7 = 0
{1 => 10, 2 => 20}.each { |k, v| d7 += v }     # 30

d8 = 0
"abc".each_char { |c| d8 += 1 }                # 3

# ---- NESTED inline-yield accumulation (method yields; caller block does +=) ----
def g_times
  3.times { |i| yield i }
end
n1 = 0
g_times { |i| n1 += 1 }                         # 3 iterations

def g_upto
  1.upto(3) { |i| yield i }
end
n2 = 0
g_upto { |i| n2 += i }                          # 6

def g_downto
  3.downto(1) { |i| yield i }
end
n3 = 0
g_downto { |i| n3 += i }                        # 6

def g_range
  (1..3).each { |i| yield i }
end
n4 = 0
g_range { |i| n4 += i }                         # 6

def g_arr_static
  [10, 20, 30].each { |x| yield x }
end
n5 = 0
g_arr_static { |x| n5 += x }                    # 60

def g_arr_dyn
  a = [10, 20, 30]
  a.each { |x| yield x }
end
n6 = 0
g_arr_dyn { |x| n6 += x }                       # 60

def g_hash
  {1 => 10, 2 => 20}.each { |k, v| yield k, v }
end
n7 = 0
g_hash { |k, v| n7 += v }                       # 30

STDERR.puts "D: #{d1} #{d2} #{d3} #{d4} #{d5} #{d6} #{d7} #{d8}"
STDERR.puts "N: #{n1} #{n2} #{n3} #{n4} #{n5} #{n6} #{n7}"
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

expected="D: 3 6 6 6 60 60 30 3
N: 3 6 6 6 60 60 30"

if [[ "$stderr_text" == "$expected" ]]; then
  echo "fixed: loop-family nested inline-yield accumulation threaded correctly"
  exit 0
fi

echo "unexpected output (expected:"
printf '%s\n' "$expected"
echo ")"
cat "$RUN_OUT"
exit 1
