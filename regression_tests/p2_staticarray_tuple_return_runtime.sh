#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
SOURCE="$ROOT_DIR/regression_tests/stage2_tuple_destructure_union_repro.cr"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/adamas_staticarray_tuple_return.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "p2_staticarray_tuple_return_runtime_failed: compiler is not executable: $COMPILER" >&2
  exit 2
fi

BIN="$TMP_DIR/repro"
COMPILE_LOG="$TMP_DIR/compile.log"
RUN_LOG="$TMP_DIR/run.log"

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 120 4096 \
  "$SOURCE" -o "$BIN" >"$COMPILE_LOG" 2>&1
compile_rc=$?
set -e

if [[ $compile_rc -ne 0 ]]; then
  echo "p2_staticarray_tuple_return_runtime_failed: compile failed rc=$compile_rc" >&2
  tail -120 "$COMPILE_LOG" >&2 || true
  exit 1
fi

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$BIN" 5 512 >"$RUN_LOG" 2>&1
run_rc=$?
set -e

if [[ $run_rc -ne 0 ]]; then
  echo "p2_staticarray_tuple_return_runtime_failed: run failed rc=$run_rc" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

actual="$(awk '
  /^=== STDOUT ===$/ { capture = 1; next }
  /^=== STDERR ===$/ { capture = 0 }
  capture { print }
' "$RUN_LOG")"

if [[ "$actual" != $'65\n3' ]]; then
  echo "p2_staticarray_tuple_return_runtime_failed: expected stdout 65\\n3" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

echo "p2_staticarray_tuple_return_runtime_ok"
