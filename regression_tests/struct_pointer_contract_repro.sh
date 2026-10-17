#!/usr/bin/env bash
# Regression for the Pointer(T) contract of user structs: a Pointer(WidePod) from
# pointerof(@field), pointerof(local), Array#to_unsafe and Pointer.malloc (and pointerof of a
# C lib struct local) must agree with
# the underlying storage on read, write, stride, clear and copy independence.
# Expected output is produced by the original Crystal compiler.
# Usage: regression_tests/struct_pointer_contract_repro.sh <compiler>
# For adamas, export CRYSTAL_PATH=<pristine crystal>/src when the baked stdlib
# path is not the pristine one.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
SRC="$ROOT_DIR/regression_tests/struct_pointer_contract.cr"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/struct_pointer_contract.XXXXXX")"
BIN="$TMP_DIR/repro.bin"
OUT="$TMP_DIR/stdout"
EXPECTED="$TMP_DIR/expected"
RUN_LOG="$TMP_DIR/run.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

compile_cmd=()
if [[ "$(basename "$COMPILER")" == "crystal" ]]; then
  compile_cmd=("$COMPILER" build "$SRC" -o "$BIN")
else
  compile_cmd=("$COMPILER" "$SRC" -o "$BIN")
fi

if ! "${compile_cmd[@]}" >"$TMP_DIR/compile.log" 2>&1; then
  echo "FAIL: compile failed"
  cat "$TMP_DIR/compile.log"
  exit 1
fi

printf '%s\n' \
  "sizeof=24" \
  "field.read=6" \
  "field.write=60" \
  "field.snapshot=6" \
  "field.bump=61" \
  "field.held=60" \
  "array.stride=24" \
  "array.read1=999" \
  "array.index1=999" \
  "array.write0=555" \
  "array.first=888" \
  "array.total=2331" \
  "raw.stride=32" \
  "raw.zero_gen=0" \
  "raw.touch1=true/1" \
  "raw.touch2=true/2" \
  "raw.pod1=444" \
  "raw.clear1=false/0/0" \
  "raw.after_clear2=true/2" \
  "local.read=6" \
  "local.fill=600" \
  "local.bump=601" \
  "local.copy=601" \
  "local.after=600" \
  "local.direct=334" \
  "lib.read=5" \
  "lib.write=9" \
  "lib.back=11" >"$EXPECTED"

set +e
RUN_SAFE_PASSTHROUGH_STDIO=1 "$ROOT_DIR/scripts/run_safe.sh" "$BIN" 10 512 \
  >"$OUT" 2>"$RUN_LOG"
run_status=$?
set -e

if [[ $run_status -ne 0 ]]; then
  echo "FAIL: run exited with $run_status"
  cat "$RUN_LOG"
  echo "--- partial stdout ---"
  cat "$OUT"
  exit 1
fi

if ! cmp -s "$EXPECTED" "$OUT"; then
  echo "FAIL: struct Pointer(T) results differ from Crystal"
  diff "$EXPECTED" "$OUT" || true
  exit 1
fi

echo "PASS: struct Pointer(T) agrees with field storage on read/write/stride/copy"
