#!/usr/bin/env bash
# Regression target: V2-generated binaries must be able to use Tuple keys with
# a nilable field in Hash. This shape matches MIR virtual-dispatch cache keys:
# {class_name, method_suffix, arg_count : Int32?, allow_module_method}.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hash_tuple_key.XXXXXX")"
OUT="$TMP_DIR/hash_tuple_key_repro"
LOG="$TMP_DIR/compile.log"
RUN_LOG="$TMP_DIR/run.log"
trap 'rm -rf "$TMP_DIR"' EXIT

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 1024 "$ROOT_DIR/regression_tests/hash_tuple_key_nilable_field_repro.cr" -o "$OUT" >"$LOG" 2>&1
compile_status=$?
set -e

if [[ $compile_status -ne 0 ]]; then
  echo "FAIL: compiler could not compile hash tuple-key repro (status $compile_status)" >&2
  tail -120 "$LOG" >&2
  exit 1
fi

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$OUT" 5 512 >"$RUN_LOG" 2>&1
run_status=$?
set -e

if [[ $run_status -ne 0 ]]; then
  echo "FAIL: hash tuple-key repro exited $run_status" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

if ! grep -Fxq "true" "$RUN_LOG" || ! grep -Fxq "ok" "$RUN_LOG"; then
  echo "FAIL: expected Hash tuple-key lookup to print true and ok" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

echo "hash_tuple_key_nilable_field_ok"
