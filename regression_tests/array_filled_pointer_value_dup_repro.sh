#!/usr/bin/env bash
# Regression: the Array.new(size, value) fast-path used the i32 filled-array
# helper for every non-Bool value. Pointer-valued arrays, such as Array(String),
# received a 4-byte-stride backing buffer. A later Array#dup copied pointer-size
# elements and read past the end of that buffer.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/array_filled_pointer_value_dup.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
COMPILE_LOG="$TMP_DIR/compile.log"
RUN_LOG="$TMP_DIR/run.log"
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$SRC" <<'CR'
a = Array(String).new(2, "x")
b = a.dup
puts "RESULT=#{b.size},#{b[0]}"
STDOUT.flush
CR

set +e
ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:-} -fsanitize=address" \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 2048 "$SRC" -o "$BIN" >"$COMPILE_LOG" 2>&1
compile_status=$?
set -e
if [[ $compile_status -ne 0 ]]; then
  echo "FAIL: compile failed (status $compile_status)"
  cat "$COMPILE_LOG"
  exit 2
fi

set +e
ASAN_OPTIONS='detect_leaks=0:abort_on_error=1:symbolize=1' \
  "$ROOT_DIR/scripts/run_safe.sh" "$BIN" 5 512 >"$RUN_LOG" 2>&1
run_status=$?
set -e

result_line="$(grep -E '^RESULT=' "$RUN_LOG" | head -1 || true)"
if [[ $run_status -eq 0 && "$result_line" == "RESULT=2,x" ]]; then
  echo "PASS: pointer-valued Array.new(size, value).dup uses valid storage"
  exit 0
fi

echo "FAIL: pointer-valued filled array still miscompiled"
echo "run status: $run_status"
cat "$RUN_LOG"
exit 1
