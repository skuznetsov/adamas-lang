#!/usr/bin/env bash
# Stock/lazy/eager control for lexical ownership of constructor defaults.
# The HIR split-arena spec is the direct regression oracle; this runtime fixture
# protects computed defaults, aliases, inheritance, and included initializers.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-$(command -v crystal || true)}"
FIXTURE="$ROOT_DIR/regression_tests/fixtures/monitor_default_lexical_context/monitor_default_lexical_context.cr"

if [[ ! -x "$ADAMAS_BIN" ]]; then
  echo "ERROR: Adamas compiler not found: $ADAMAS_BIN" >&2
  exit 2
fi
if [[ -z "$CRYSTAL_BIN" || ! -x "$CRYSTAL_BIN" ]]; then
  echo "ERROR: original Crystal compiler not found; set CRYSTAL_BIN" >&2
  exit 2
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/monitor-default-context.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

run_and_check() {
  local mode="$1"
  local compiler="$2"
  local binary="$3"
  local expected_file="$4"
  shift 4
  local -a mode_env=("$@")
  local compile_log="$WORK_DIR/$mode.compile.log"
  local run_log="$WORK_DIR/$mode.run.log"
  local actual="$WORK_DIR/$mode.stdout"

  if [[ "$mode" == stock ]]; then
    if ! "$SAFE_RUNNER" "$compiler" 120 8192 build --prelude=empty \
        "$FIXTURE" -o "$binary" >"$compile_log" 2>&1; then
      cat "$compile_log" >&2
      echo "FAIL: stock Crystal rejected the fixture" >&2
      exit 1
    fi
  else
    if ! env "${mode_env[@]}" "$SAFE_RUNNER" "$compiler" 120 8192 \
        "$FIXTURE" --no-prelude --no-debug --no-ast-cache --no-llvm-cache \
        -o "$binary" >"$compile_log" 2>&1; then
      cat "$compile_log" >&2
      echo "FAIL: Adamas did not compile the fixture ($mode)" >&2
      exit 1
    fi
  fi

  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$binary" 5 512 \
      >"$actual" 2>"$run_log"; then
    cat "$run_log" >&2
    echo "FAIL: fixture binary did not run ($mode)" >&2
    exit 1
  fi
  if ! cmp -s "$expected_file" "$actual"; then
    echo "FAIL: output differs in $mode mode" >&2
    diff -u "$expected_file" "$actual" >&2 || true
    exit 1
  fi
}

printf 'ACDE\n' >"$WORK_DIR/expected.stdout"
run_and_check stock "$CRYSTAL_BIN" "$WORK_DIR/stock" "$WORK_DIR/expected.stdout"

for mode in lazy eager; do
  mode_env=(-u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
  if [[ "$mode" == eager ]]; then
    mode_env+=(ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1)
  fi
  run_and_check "$mode" "$ADAMAS_BIN" "$WORK_DIR/adamas-$mode" \
    "$WORK_DIR/expected.stdout" "${mode_env[@]}"
done

echo "PASS: constructor defaults retain declaration lexical ownership (ACDE)"
