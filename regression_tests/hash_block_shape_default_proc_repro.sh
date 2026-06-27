#!/usr/bin/env bash
# Regression: block-shaped Hash.new wrappers must keep the heap Proc default
# provider as the non-nil arm of `Nil | Proc(...)`, while coexisting
# initial_capacity/default-value constructors keep their own call shapes.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hash_block_shape_default_proc.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
COMPILE_LOG="$TMP_DIR/compile.log"
RUN_LOG="$TMP_DIR/run.log"
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$SRC" <<'CR'
h1 = Hash(String, Int32).new(initial_capacity: 24) { 1 }
h2 = Hash(String, Int32).new(0)
puts "A=#{h1["x"]}"
puts "B=#{h2["y"]}"
STDOUT.flush
CR

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 2048 "$SRC" -o "$BIN" >"$COMPILE_LOG" 2>&1
compile_status=$?
set -e
if [[ $compile_status -ne 0 ]]; then
  echo "FAIL: compile failed (status $compile_status)"
  cat "$COMPILE_LOG"
  exit 2
fi

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$BIN" 5 512 >"$RUN_LOG" 2>&1
run_status=$?
set -e

a_line="$(grep -E '^A=' "$RUN_LOG" | head -1 || true)"
b_line="$(grep -E '^B=' "$RUN_LOG" | head -1 || true)"
if [[ $run_status -eq 0 && "$a_line" == "A=1" && "$b_line" == "B=0" ]]; then
  echo "PASS: Hash block wrapper default Proc shape is preserved"
  exit 0
fi

echo "FAIL: Hash block wrapper/default Proc regression reproduced"
echo "expected: A=1 / B=0"
echo "actual:   ${a_line:-<no A line>} / ${b_line:-<no B line>} (status $run_status)"
cat "$RUN_LOG"
exit 1
