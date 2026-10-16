#!/usr/bin/env bash
# Regression for interleaved buffered reads: gets / read / read_byte / peek on one
# IO (a File and STDIN fed by a pipe) must consume bytes in program order and
# agree with the original Crystal compiler on content, remainder and EOF.
# Usage: regression_tests/buffered_read_order_repro.sh <compiler>
# For adamas, export CRYSTAL_PATH=<pristine crystal>/src when the baked stdlib
# path is not the pristine one.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
SRC="$ROOT_DIR/regression_tests/buffered_read_order.cr"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/buffered_read_order.XXXXXX")"
BIN="$TMP_DIR/repro.bin"
INPUT="$TMP_DIR/input.txt"
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

# Input: short lines, a UTF-8 CRLF line, a 5000-byte line (longer than any
# fixed 4 KiB line buffer), then 30 bytes without a trailing newline.
{
  printf 'alpha\nbravo\ncharlie\ndelta\n\303\234nicode line\r\n'
  head -c 4996 /dev/zero | tr '\0' L | sed 's/^/HEAD/'
  printf 'TAIL\n'
  printf '0123456789abcdefghijKLMNOPQRST'
} >"$INPUT"

expected_block() {
  local tag="$1"
  printf '%s\n' \
    "$tag.gets1=[alpha] bs=5 sz=5" \
    "$tag.read3=3:[bra]" \
    "$tag.byte1=v" \
    "$tag.gets2=[o] bs=1 sz=1" \
    "$tag.gets3=[charlie
] bs=8 sz=8" \
    "$tag.byte2=d" \
    "$tag.byte3=e" \
    "$tag.gets_t=[lt] bs=2 sz=2" \
    "$tag.gets4=[a] bs=1 sz=1" \
    "$tag.gets_crlf=[$(printf '\303\234')nicode line] bs=13 sz=12" \
    "$tag.long bs=5004 head=HEAD tail=TAIL" \
    "$tag.peek_nonempty=true" \
    "$tag.read20=20:[0123456789abcdefghij]" \
    "$tag.rest=[KLMNOPQRST] bs=10 sz=10" \
    "$tag.eof_gets=nil" \
    "$tag.eof_byte=nil" \
    "$tag.eof_read=0"
}
{
  expected_block file
  expected_block stdin
} >"$EXPECTED"

set +e
cat "$INPUT" | RUN_SAFE_PASSTHROUGH_STDIO=1 "$ROOT_DIR/scripts/run_safe.sh" "$BIN" 10 512 \
  "$INPUT" >"$OUT" 2>"$RUN_LOG"
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
  echo "FAIL: read results differ from Crystal"
  diff "$EXPECTED" "$OUT" || true
  exit 1
fi

echo "PASS: interleaved gets/read/read_byte/peek consume File and pipe in order"
