#!/usr/bin/env bash
# RED oracle: `::Array({Int32, Int32}).new(N)` (global-scoped generic Array with a
# Tuple element) mis-resolves and demands a phantom `Array#call(Tuple(...))` method
# that does not exist, emitting an abort STUB (`STUB CALLED: Array$Dcall$$Tuple...`).
#
# Trigger is the LEADING `::` combined with a Tuple element type:
#   ::Array({Int32,Int32}).new(4)   -> STUB   (this file)
#     Array({Int32,Int32}).new(4)   -> OK     (no `::`)
#   ::Array(Int32).new(4)           -> OK     (non-Tuple element)
#
# This is the s2 self-host blocker's STUB manifestation: emit_functions_parallel
# uses `func_costs = ::Array({Int32, Int32}).new(total)`.
#
# Neither `<<` nor iteration is required — mere construction reproduces it.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cc_array_tuple_new.XXXXXX")"
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
costs = ::Array({Int32, Int32}).new(4)
costs << {1, 100}
costs << {2, 50}
costs.each do |idx, cost|
  STDERR.puts idx
  STDERR.puts cost
end
STDERR.flush
CR

"${compile_cmd[@]}" >/dev/null 2>&1 || { echo "FAIL: compile error"; exit 1; }

set +e
"$BIN" >"$RUN_LOG" 2>&1
run_status=$?
set -e

if grep -q "STUB CALLED" "$RUN_LOG"; then
  echo "reproduced: phantom Array#call stub demanded for ::Array(Tuple)"
  echo "--- run log ---"; cat "$RUN_LOG"
  exit 1
fi

# Expect the four printed values in order.
expected=$'1\n100\n2\n50'
actual="$(cat "$RUN_LOG")"
if [[ "$actual" != "$expected" ]]; then
  echo "FAIL: unexpected output (run_status=$run_status)"
  echo "--- expected ---"; printf '%s\n' "$expected"
  echo "--- actual ---"; printf '%s\n' "$actual"
  exit 1
fi

echo "PASS: ::Array(Tuple).new iterates correctly, no phantom Array#call stub"
exit 0
