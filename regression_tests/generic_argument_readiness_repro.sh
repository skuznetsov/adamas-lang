#!/usr/bin/env bash
# Registered type identities settle generic arguments; nilable arguments remain concrete.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
FIXTURES="$ROOT_DIR/regression_tests/fixtures/generic_argument_readiness"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/generic_argument_readiness.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
printf 'A\n' >"$WORK_DIR/expected"
for mode in lazy eager; do
  env_args=(-u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
  if [[ "$mode" == eager ]]; then
    env_args+=(ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1)
  fi
  for fixture in "$FIXTURES"/*.cr; do
    name="$(basename "$fixture" .cr)"
    binary="$WORK_DIR/$name.$mode"
    if ! env "${env_args[@]}" "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 8192 \
        "$fixture" --no-prelude --no-debug --no-ast-cache --no-llvm-cache \
        -o "$binary" >"$WORK_DIR/build.log" 2>&1; then
      cat "$WORK_DIR/build.log" >&2
      exit 1
    fi
    status=0
    RUN_SAFE_PASSTHROUGH_STDIO=1 "$ROOT_DIR/scripts/run_safe.sh" "$binary" 5 512 \
        >"$WORK_DIR/actual" 2>"$WORK_DIR/run.log" || status=$?
    if [[ "$status" != 0 ]] || ! cmp -s "$WORK_DIR/expected" "$WORK_DIR/actual"; then
      echo "FAIL: $name ($mode), exit $status" >&2
      cat "$WORK_DIR/run.log" >&2
      od -An -tx1 "$WORK_DIR/actual" >&2
      exit 1
    fi
  done
done
echo "PASS: concrete, nilable and plain generic constructor arguments"
