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
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal || true)}"
[[ -x "$COMPILER" && -x "$ORIGINAL" ]] || {
  echo "Both the candidate and ORIGINAL_CRYSTAL_BIN must be executable" >&2
  exit 2
}
SRC="$ROOT_DIR/regression_tests/buffered_read_order.cr"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/buffered_read_order.XXXXXX")"
INPUT="$TMP_DIR/input.txt"
EXPECTED="$TMP_DIR/expected"

cleanup() {
  local status=$?
  rm -rf "$TMP_DIR/original.cache" "$TMP_DIR/candidate.cache"
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$TMP_DIR" >&2
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

DEFAULT_LINK_FLAGS=""
[[ "$(uname -s)" != Darwin ]] || DEFAULT_LINK_FLAGS=-fuse-ld=/usr/bin/ld
ORIGINAL_LINK_FLAGS="${ORIGINAL_LINK_FLAGS-$DEFAULT_LINK_FLAGS}"
export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS-$DEFAULT_LINK_FLAGS}"

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

stages=(original candidate)
[[ "${ORIGINAL_ONLY:-0}" != 1 ]] || stages=(original)
for stage in "${stages[@]}"; do
  bin="$TMP_DIR/$stage.bin"
  out="$TMP_DIR/$stage.stdout"
  run_log="$TMP_DIR/$stage.run.log"
  if [[ "$stage" == original ]]; then
    compile_cmd=("$ORIGINAL" build "$SRC" -o "$bin" --no-debug)
    [[ -z "$ORIGINAL_LINK_FLAGS" ]] || compile_cmd+=("--link-flags=$ORIGINAL_LINK_FLAGS")
  else
    compile_cmd=("$COMPILER" "$SRC" -o "$bin" --no-debug --no-ast-cache --no-llvm-cache)
  fi
  if ! env "CRYSTAL_CACHE_DIR=$TMP_DIR/$stage.cache" \
    "$ROOT_DIR/scripts/run_safe.sh" "${compile_cmd[0]}" 120 4096 \
    "${compile_cmd[@]:1}" >"$TMP_DIR/$stage.compile.log" 2>&1; then
    echo "FAIL: $stage compile failed" >&2
    tail -50 "$TMP_DIR/$stage.compile.log" >&2
    exit 1
  fi
  rm -rf "$TMP_DIR/$stage.cache"
  if ! cat "$INPUT" | RUN_SAFE_PASSTHROUGH_STDIO=1 \
    "$ROOT_DIR/scripts/run_safe.sh" "$bin" 10 512 "$INPUT" \
    >"$out" 2>"$run_log"; then
    echo "FAIL: $stage execution failed" >&2
    tail -40 "$run_log" >&2
    exit 1
  fi
  if ! cmp -s "$EXPECTED" "$out"; then
    echo "FAIL: $stage read results differ from the oracle" >&2
    diff -u "$EXPECTED" "$out" >&2 || true
    exit 1
  fi
done
if [[ "${ORIGINAL_ONLY:-0}" != 1 ]]; then
  cmp "$TMP_DIR/original.stdout" "$TMP_DIR/candidate.stdout"
fi

echo "PASS: interleaved gets/read/read_byte/peek consume File and pipe in order"
