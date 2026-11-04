#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
FIXTURES="$ROOT/regression_tests/fixtures/bare_proc_parameter"
SAFE="$ROOT/scripts/run_safe.sh"
ADAMAS="${ADAMAS_BIN:-${1:-$ROOT/bin/adamas}}"
CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/adamas-bare-proc-parameter.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT

export CRYSTAL_CACHE_DIR="$WORK/cache"
export CRYSTAL_PATH="${CRYSTAL_PATH:-$(RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$CRYSTAL" 10 1024 env CRYSTAL_PATH)}"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO

compile() {
  local compiler="$1" fixture="$2" output="$3"
  if [[ "$compiler" == stock ]]; then
    "$SAFE" "$CRYSTAL" 20 2048 build --prelude=empty --no-debug "$FIXTURES/$fixture.cr" -o "$output"
  else
    local eager=0
    if [[ "$compiler" == eager ]]; then eager=1; fi
    ADAMAS_EAGER_HIR="$eager" "$SAFE" "$ADAMAS" 20 2048 --no-prelude --no-debug --no-ast-cache --no-llvm-cache "$FIXTURES/$fixture.cr" -o "$output"
  fi
}

expect_rejection() {
  local compiler="$1" fixture="$2" diagnostic="$3" code=0
  local output="$WORK/$fixture.$compiler"
  compile "$compiler" "$fixture" "$output" >"$output.log" 2>&1 || code=$?
  if [[ "$code" != 1 ]] || ! grep -Eiq "$diagnostic" "$output.log"; then
    cat "$output.log" >&2
    exit 1
  fi
}

for compiler in stock lazy eager; do
  for fixture in valid shadow metaclass; do
    output="$WORK/$fixture.$compiler"
    if ! compile "$compiler" "$fixture" "$output" >"$output.compile.log" 2>&1; then
      cat "$output.compile.log" >&2
      exit 1
    fi
    if ! "$SAFE" "$output" 5 512 >"$output.run.log" 2>&1; then
      cat "$output.run.log" >&2
      exit 1
    fi
  done

  expect_rejection "$compiler" invalid_input "Proc\(Int32, Int32\)#call.*Int64"
  expect_rejection "$compiler" wrong_kind "Proc\(Int32\.class, Int32\)#call.*Int32"
  expect_rejection "$compiler" nonproc "(no overload matches|expected argument).*apply"
  printf 'PASS bare Proc parameter (%s)\n' "$compiler"
done
