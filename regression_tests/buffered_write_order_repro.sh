#!/usr/bin/env bash
# Regression for mixed buffered writes: write_byte/print(Char) and write(Slice)/print(String)
# must reach STDOUT, IO::Memory and a File in program order.
# Usage: regression_tests/buffered_write_order_repro.sh <compiler>
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
SRC="$ROOT_DIR/regression_tests/buffered_write_order.cr"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/buffered_write_order.XXXXXX")"
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

# STDOUT goes to a regular file, so it is fully buffered (no flush-on-newline).
set +e
RUN_SAFE_PASSTHROUGH_STDIO=1 "$ROOT_DIR/scripts/run_safe.sh" "$BIN" 10 512 \
  "$TMP_DIR/file.out" >"$OUT" 2>"$RUN_LOG"
run_status=$?
set -e

printf '%s' 'payload
Abyte
abcdefgh1
no-newline:xy
tail-z!
memory="abcdefgh1\nno-newline:xy\nMend"
file="abcdefgh1\nno-newline:xy\nFend"
<' >"$EXPECTED"
head -c 9000 /dev/zero | tr '\0' x >>"$EXPECTED"
printf '%s' '>mid' >>"$EXPECTED"
head -c 8190 /dev/zero | tr '\0' y >>"$EXPECTED"
printf '%s' '|end
final-no-newline.sync-on' >>"$EXPECTED"

if [[ $run_status -ne 0 ]]; then
  echo "FAIL: run exited with $run_status"
  cat "$RUN_LOG"
  exit 1
fi

if ! cmp -s "$EXPECTED" "$OUT"; then
  echo "FAIL: output order differs from Crystal"
  echo "--- expected ---"
  cat "$EXPECTED"
  echo
  echo "--- actual ---"
  cat "$OUT"
  echo
  cmp "$EXPECTED" "$OUT" || true
  exit 1
fi

if ! grep -qx 'Err!' "$RUN_LOG"; then
  echo "FAIL: STDERR line 'Err!' missing"
  cat "$RUN_LOG"
  exit 1
fi

echo "PASS: buffered write order matches Crystal"
