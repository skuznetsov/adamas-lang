#!/usr/bin/env bash
# End-to-end stdlib control for anonymous-block forwarding through File/Path
# joining and Tuple#reduce, at two different tuple arities.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
ORIGINAL_CRYSTAL="${ORIGINAL_CRYSTAL:-crystal}"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"
SOURCE="$ROOT_DIR/regression_tests/file_join_tuple_reduce_union_callback.cr"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/file-join-tuple-reduce.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

for mode in original adamas; do
  if [[ "$mode" == original ]]; then
    build=("$ORIGINAL_CRYSTAL" 180 8192 build "$SOURCE")
  else
    build=("$COMPILER" 180 8192 "$SOURCE" --no-llvm-cache)
  fi
  if ! "$RUN_SAFE" "${build[@]}" -o "$WORK_DIR/$mode" >"$WORK_DIR/$mode.compile.log" 2>&1; then
    echo "FAIL: $mode File.join compilation" >&2
    tail -40 "$WORK_DIR/$mode.compile.log" >&2
    exit 1
  fi
  if ! "$RUN_SAFE" "$WORK_DIR/$mode" 5 512 >"$WORK_DIR/$mode.run.log" 2>&1; then
    echo "FAIL: $mode File.join runtime" >&2
    cat "$WORK_DIR/$mode.run.log" >&2
    exit 1
  fi
  actual="$(awk '
    /^=== STDOUT ===$/ { capture = 1; next }
    /^=== STDERR ===$/ { capture = 0 }
    capture { print }
  ' "$WORK_DIR/$mode.run.log")"
  if [[ "$actual" != $'OK join3=a/b/c\nOK join=./bb.cr\nDONE' ]]; then
    echo "FAIL: $mode File.join output" >&2
    cat "$WORK_DIR/$mode.run.log" >&2
    exit 1
  fi
done

echo "PASS: stdlib File.join preserves both tuple arities and complete output"
