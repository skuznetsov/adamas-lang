#!/usr/bin/env bash
# A type predicate must never discard extra arguments before proving a type.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
FIXTURES="$ROOT_DIR/regression_tests/fixtures/is_a_argument_boundary"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/is_a_argument_boundary.XXXXXX")"
trap 'rm -rf -- "$WORK_DIR"' EXIT
for mode in lazy eager; do
  env_args=(-u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
  if [[ "$mode" == eager ]]; then
    env_args+=(ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1)
  fi
  binary="$WORK_DIR/valid.$mode"
  if ! env "${env_args[@]}" "$SAFE" "$COMPILER" 60 8192 \
      "$FIXTURES/valid.cr" --no-prelude --no-debug --no-ast-cache --no-llvm-cache \
      -o "$binary" >"$WORK_DIR/build.log" 2>&1; then
    cat "$WORK_DIR/build.log" >&2
    exit 1
  fi
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$binary" 5 512 \
    >"$WORK_DIR/actual" 2>"$WORK_DIR/run.log"
  cmp "$FIXTURES/valid.expected" "$WORK_DIR/actual"
  for source in "$FIXTURES/"*_rejected.cr; do
    status=0
    env "${env_args[@]}" "$SAFE" "$COMPILER" 60 8192 \
      "$source" --no-prelude --no-debug --no-ast-cache --no-llvm-cache \
      -o "$WORK_DIR/rejected.$mode" >"$WORK_DIR/rejected.log" 2>&1 || status=$?
    if [[ "$status" != 1 ]]; then
      cat "$WORK_DIR/rejected.log" >&2
      echo "FAIL: invalid is_a? syntax was not rejected ($source, $mode HIR)" >&2
      exit 1
    fi
    grep -Fq 'expecting' "$WORK_DIR/rejected.log"
  done
done
echo 'PASS: is_a? owns exactly one nonempty type argument'
