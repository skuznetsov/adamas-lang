#!/usr/bin/env bash
# A direct initialize call returns its source result; .new returns the object.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
FIXTURES="$ROOT_DIR/regression_tests/fixtures/initializer_source_result"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/initializer_source_result.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
for mode in lazy eager; do
  env_args=(-u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
  if [[ "$mode" == eager ]]; then
    env_args+=(ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1)
  fi
  for name in opaque_direct_result constructor_object_result delegating_named_result super_direct_result constructor_bottom; do
    binary="$WORK_DIR/$name.$mode"
    if ! env "${env_args[@]}" "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 8192 \
        "$FIXTURES/$name.cr" --no-prelude --no-debug --no-ast-cache --no-llvm-cache \
        -o "$binary" >"$WORK_DIR/build.log" 2>&1; then
      cat "$WORK_DIR/build.log" >&2
      exit 1
    fi
    status=0
    printf B | RUN_SAFE_PASSTHROUGH_STDIO=1 "$ROOT_DIR/scripts/run_safe.sh" "$binary" 5 512 \
        >"$WORK_DIR/actual" 2>"$WORK_DIR/run.log" || status=$?
    expected_status=0
    if [[ "$name" == constructor_bottom ]]; then
      expected_status=67
      : >"$WORK_DIR/expected"
    else
      printf 'B\n' >"$WORK_DIR/expected"
    fi
    if [[ "$status" != "$expected_status" ]] || ! cmp -s "$WORK_DIR/expected" "$WORK_DIR/actual"; then
      echo "FAIL: $name ($mode), exit $status, expected $expected_status" >&2
      cat "$WORK_DIR/run.log" >&2
      od -An -tx1 "$WORK_DIR/actual" >&2
      exit 1
    fi
  done
done
echo "PASS: initializer source values, constructor objects and bottom effects agree"
