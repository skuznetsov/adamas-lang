#!/usr/bin/env bash
# Macro-expanded class assignments share the ordinary field/default contract.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
FIXTURES="$ROOT_DIR/regression_tests/fixtures/macro_ivar_assignment"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macro_ivar_assignment.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
for mode in lazy eager; do
  env_args=(-u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
  if [[ "$mode" == eager ]]; then
    env_args+=(ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1)
  fi
  for item in direct_control:A selected_if:A selected_else:A begin_expansion:A for_expansion:A; do
    name="${item%%:*}"
    expected="${item#*:}"
    binary="$WORK_DIR/$name.$mode"
    if ! env "${env_args[@]}" "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 8192 \
        "$FIXTURES/$name.cr" --no-prelude --no-debug --no-ast-cache --no-llvm-cache \
        -o "$binary" >"$WORK_DIR/build.log" 2>&1; then
      cat "$WORK_DIR/build.log" >&2
      exit 1
    fi
    RUN_SAFE_PASSTHROUGH_STDIO=1 "$ROOT_DIR/scripts/run_safe.sh" "$binary" 5 512 \
      >"$WORK_DIR/actual" 2>"$WORK_DIR/run.log"
    printf '%s\n' "$expected" >"$WORK_DIR/expected"
    if ! cmp -s "$WORK_DIR/expected" "$WORK_DIR/actual"; then
      echo "FAIL: $name ($mode)" >&2
      od -An -tx1 "$WORK_DIR/actual" >&2
      exit 1
    fi
  done
done
echo "PASS: macro-expanded class fields retain their types and defaults"
