#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
FIXTURES="$ROOT/regression_tests/fixtures/typeof_local_proc"
SAFE="$ROOT/scripts/run_safe.sh"
ADAMAS="${ADAMAS_BIN:-${1:-$ROOT/bin/adamas}}"
CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/adamas-typeof-local-proc.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT

export CRYSTAL_CACHE_DIR="$WORK/cache"
export CRYSTAL_PATH="${CRYSTAL_PATH:-$(RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$CRYSTAL" 10 1024 env CRYSTAL_PATH)}"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO

compile() {
  local compiler="$1" fixture="$2" output="$3"
  local prelude=()
  if [[ "$compiler" == stock ]]; then
    if [[ "$fixture" == identity ]]; then prelude=(--prelude=empty); fi
    "$SAFE" "$CRYSTAL" 60 4096 build "${prelude[@]}" --no-debug "$FIXTURES/$fixture.cr" -o "$output"
  else
    local eager=0
    if [[ "$compiler" == eager ]]; then eager=1; fi
    if [[ "$fixture" == identity ]]; then prelude=(--no-prelude); fi
    ADAMAS_EAGER_HIR="$eager" "$SAFE" "$ADAMAS" 90 4096 "${prelude[@]}" --no-debug --no-ast-cache --no-llvm-cache "$FIXTURES/$fixture.cr" -o "$output"
  fi
}

expect_native_success() {
  local compiler="$1" fixture="$2" output="$WORK/$1.$2"
  if ! compile "$compiler" "$fixture" "$output" >"$output.compile.log" 2>&1; then
    cat "$output.compile.log" >&2
    return 1
  fi
  if ! "$SAFE" "$output" 5 512 >"$output.run.log" 2>&1; then
    cat "$output.run.log" >&2
    return 1
  fi
}

for compiler in stock lazy eager; do
  expect_native_success "$compiler" identity
done

# These cases use the installed stdlib's Box implementation.
for compiler in stock lazy; do
  for fixture in boxed nullable metaclass; do
    expect_native_success "$compiler" "$fixture"
  done
  output="$WORK/$compiler.wrong_kind"
  code=0
  compile "$compiler" wrong_kind "$output" >"$output.log" 2>&1 || code=$?
  if [[ "$code" != 1 ]] || ! grep -Eiq 'Proc\(Int32\.class, Int64\)#call.*Int32' "$output.log"; then
    cat "$output.log" >&2
    exit 1
  fi
done
echo "PASS local Proc typeof (stock, lazy, eager; Box with installed prelude)"
