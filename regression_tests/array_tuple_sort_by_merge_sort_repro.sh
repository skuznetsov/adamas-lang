#!/usr/bin/env bash
# RED oracle: sort_by! (and the underlying Array(Tuple(...))#sort! ->
# Slice#merge_sort!) on an array of tuples corrupts memory and crashes
# (EXC_BAD_ACCESS in the merge_sort comparator block / Slice range slicing).
#
# This is the s2 self-host EMISSION-phase blocker, unmasked once the
# ::Array({T,U}) call-stub was fixed (7c2f06b9): emit_functions_parallel does
#   func_costs = ::Array({Int32, Int32}).new(total)
#   func_costs.sort_by! { |_, cost| -cost }
# Backtrace (s2 build): __crystal_block_proc_N (addr 0x60) <- Slice(UInt8)#cmp
#   <- Slice#merge_sort! <- Array(Tuple(Tuple(Int32,Int32),Int32))#sort!$block
#   <- emit_functions_parallel.
#
# Reproduces WITHOUT `::` and with a plain array literal, so the root is the
# tuple-in-Slice/merge_sort path, NOT the `::Array` generic form.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/array_tuple_sort_by.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
RUN_LOG="$TMP_DIR/run.log"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

compile_cmd=()
if [[ "$(basename "$COMPILER")" == "crystal" ]]; then
  compile_cmd=("$COMPILER" build "$SRC" -o "$BIN")
else
  compile_cmd=("$COMPILER" "$SRC" -o "$BIN")
fi

cat >"$SRC" <<'CR'
costs = [{1, 100}, {2, 50}, {3, 75}]
costs.sort_by! { |_, cost| -cost }
STDERR.puts costs[0][1]
STDERR.puts costs[1][1]
STDERR.puts costs[2][1]
STDERR.flush
CR

"${compile_cmd[@]}" >/dev/null 2>&1 || { echo "FAIL: compile error"; exit 1; }

set +e
"$BIN" >"$RUN_LOG" 2>&1
run_status=$?
set -e

# Signal death (segfault/abort) => reproduced.
if [[ $run_status -ge 128 ]]; then
  echo "reproduced: sort_by! on Array(Tuple) crashed (status=$run_status)"
  echo "--- run log ---"; cat "$RUN_LOG"
  exit 1
fi

# Sorted by -cost descending: 100, 75, 50
expected=$'100\n75\n50'
actual="$(cat "$RUN_LOG")"
if [[ "$actual" != "$expected" ]]; then
  echo "FAIL: wrong sort output (status=$run_status)"
  echo "--- expected ---"; printf '%s\n' "$expected"
  echo "--- actual ---"; printf '%s\n' "$actual"
  exit 1
fi

echo "PASS: sort_by! on Array(Tuple) sorts correctly"
exit 0
