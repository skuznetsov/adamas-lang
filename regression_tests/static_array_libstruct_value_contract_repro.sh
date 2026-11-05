#!/usr/bin/env bash
# Stock-first safe oracle for StaticArray(C-struct) value storage.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="$ROOT_DIR/regression_tests/static_array_libstruct_value_contract.cr"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <stock-crystal-compiler> <candidate-adamas-compiler>" >&2
  exit 2
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/static_array_libstruct_contract.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

run_case() {
  local label="$1"
  local compiler="$2"
  local binary="$WORK_DIR/$label"
  local compile_stdout="$WORK_DIR/$label.compile.stdout"
  local compile_stderr="$WORK_DIR/$label.compile.stderr"
  local run_stdout="$WORK_DIR/$label.run.stdout"
  local run_stderr="$WORK_DIR/$label.run.stderr"

  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$compiler" 90 8192 \
      build "$FIXTURE" --no-debug -o "$binary" \
      >"$compile_stdout" 2>"$compile_stderr"; then
    cat "$compile_stdout" "$compile_stderr" >&2
    echo "$label compile failed" >&2
    return 1
  fi

  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$binary" 5 512 \
      >"$run_stdout" 2>"$run_stderr"; then
    cat "$run_stdout" "$run_stderr" >&2
    echo "$label native run failed" >&2
    return 1
  fi

  if ! printf '1111110\n' | cmp -s - "$run_stdout"; then
    cat "$run_stdout" "$run_stderr" >&2
    echo "$label output mismatch; expected 1111110\\n" >&2
    return 1
  fi
}

# Establish the original Crystal contract before compiling the candidate.
run_case stock "$1"
run_case candidate "$2"
echo "static_array_libstruct_value_contract_repro: ok"
