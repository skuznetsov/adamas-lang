#!/usr/bin/env bash
# Keep pointer-shorthand generic admission stable in lazy and eager HIR.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
FIXTURE="$ROOT_DIR/regression_tests/fixtures/generic_pointer_readiness/pointer_generic_owner.cr"
EXPECTED="$ROOT_DIR/regression_tests/fixtures/generic_pointer_readiness/pointer_generic_owner.expected"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/generic_pointer_readiness.XXXXXX")"
trap 'rm -rf -- "$WORK_DIR"' EXIT

if [[ ! -x "$SAFE" || ! -x "$COMPILER" ]]; then
  echo "ERROR: safe runner or compiler is unavailable" >&2
  exit 2
fi

for mode in lazy eager; do
  env_args=(-u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
  if [[ "$mode" == eager ]]; then
    env_args+=(ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1)
  fi

  binary="$WORK_DIR/pointer_owner.$mode"
  if ! env "${env_args[@]}" "$SAFE" "$COMPILER" 60 8192 \
      "$FIXTURE" --no-prelude --no-debug --no-ast-cache --no-llvm-cache \
      -o "$binary" >"$WORK_DIR/build.log" 2>&1; then
    cat "$WORK_DIR/build.log" >&2
    echo "FAIL: pointer generic owner did not compile ($mode HIR)" >&2
    exit 1
  fi

  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$binary" 5 512 \
      >"$WORK_DIR/actual" 2>"$WORK_DIR/run.log"; then
    cat "$WORK_DIR/run.log" >&2
    exit 1
  fi
  if ! cmp -s "$EXPECTED" "$WORK_DIR/actual"; then
    echo "FAIL: pointer generic owner output differs ($mode HIR)" >&2
    od -An -tx1 "$WORK_DIR/actual" >&2
    exit 1
  fi
done

echo "PASS: GenericPointerReadinessBox(Void*) prints A in lazy and eager HIR"
