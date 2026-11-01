#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
FIXTURES="$ROOT_DIR/regression_tests/fixtures/packed_splat_source_identity"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/packed_splat_source_identity.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
EXPECTED="$WORK_DIR/expected"
printf 'ABCDEFGEFEF\n' >"$EXPECTED"

for mode in lazy eager; do
  env_args=(-u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
  if [[ "$mode" == eager ]]; then
    env_args+=(ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1)
  fi

  binary="$WORK_DIR/main.$mode"
  if ! env "${env_args[@]}" "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 120 8192 \
      "$FIXTURES/main.cr" --no-prelude --no-debug --no-ast-cache --no-llvm-cache \
      -o "$binary" >"$WORK_DIR/$mode.build.log" 2>&1; then
    cat "$WORK_DIR/$mode.build.log" >&2
    echo "FAIL: positive fixture did not compile ($mode)" >&2
    exit 1
  fi
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$ROOT_DIR/scripts/run_safe.sh" "$binary" 5 512 \
      >"$WORK_DIR/$mode.actual" 2>"$WORK_DIR/$mode.run.log"; then
    cat "$WORK_DIR/$mode.run.log" >&2
    echo "FAIL: positive fixture did not run ($mode)" >&2
    exit 1
  fi
  if ! cmp -s "$EXPECTED" "$WORK_DIR/$mode.actual"; then
    echo "FAIL: stdout differs ($mode)" >&2
    od -An -tx1 "$WORK_DIR/$mode.actual" >&2
    exit 1
  fi

  if env "${env_args[@]}" "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 120 8192 \
      "$FIXTURES/wrong_element.cr" --no-prelude --no-debug --no-ast-cache --no-llvm-cache \
      -o "$WORK_DIR/wrong.$mode" >"$WORK_DIR/$mode.negative.log" 2>&1; then
    echo "FAIL: incompatible Bool rest element compiled ($mode)" >&2
    exit 1
  fi
  if ! grep -q 'error: no overload matches PackedWrongElement#accept for argument types (Bool)' \
      "$WORK_DIR/$mode.negative.log"; then
    cat "$WORK_DIR/$mode.negative.log" >&2
    echo "FAIL: incompatible rest was not rejected for the expected type mismatch ($mode)" >&2
    exit 1
  fi
done

echo "PASS: exact source rest overload identity survives packed Tuple specialization"
