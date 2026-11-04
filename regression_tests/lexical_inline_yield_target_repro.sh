#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
FIXTURES="$ROOT/regression_tests/fixtures"
SAFE="$ROOT/scripts/run_safe.sh"
ADAMAS="${ADAMAS_BIN:-${1:-$ROOT/bin/adamas}}"
CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/adamas-lexical-inline-yield.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT

export CRYSTAL_CACHE_DIR="$WORK/cache"
export CRYSTAL_PATH="${CRYSTAL_PATH:-$(RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$CRYSTAL" 10 1024 env CRYSTAL_PATH)}"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO

compile() {
  local compiler="$1" prelude="$2" source="$3" output="$4"
  local -a flags=()
  if [[ "$compiler" == stock ]]; then
    if [[ "$prelude" == empty ]]; then flags=(--prelude=empty); fi
    "$SAFE" "$CRYSTAL" 30 3072 build "${flags[@]}" --no-debug "$source" -o "$output"
  else
    local eager=0
    if [[ "$compiler" == eager ]]; then eager=1; fi
    if [[ "$prelude" == empty ]]; then flags=(--no-prelude); fi
    ADAMAS_EAGER_HIR="$eager" "$SAFE" "$ADAMAS" 45 3072 "${flags[@]}" --no-debug --no-ast-cache --no-llvm-cache "$source" -o "$output"
  fi
}

check_run() {
  local compiler="$1" prelude="$2" source="$3"
  local output="$WORK/${source##*/}.$compiler"
  if ! compile "$compiler" "$prelude" "$source" "$output" >"$output.compile.log" 2>&1; then
    cat "$output.compile.log" >&2
    return 1
  fi
  if ! "$SAFE" "$output" 5 512 >"$output.run.log" 2>&1; then
    cat "$output.run.log" >&2
    return 1
  fi
}

fixture="$FIXTURES/lexical_inline_yield_target.cr"
sed 's/Box(U).from/Box(Int32).from/' "$fixture" >"$WORK/wrong_result.cr"
for compiler in stock lazy eager; do
  check_run "$compiler" empty "$fixture"
  code=0
  compile "$compiler" empty "$WORK/wrong_result.cr" "$WORK/wrong_result" >"$WORK/wrong.log" 2>&1 || code=$?
  if [[ "$code" != 1 ]] || ! grep -Eiq 'expected block.*to return (::)?Int32, not Tuple\(Int32, UInt64\)' "$WORK/wrong.log"; then
    cat "$WORK/wrong.log" >&2
    exit 1
  fi
  printf 'PASS lexical inline yield target (%s)\n' "$compiler"
done

for compiler in stock lazy; do
  check_run "$compiler" installed "$FIXTURES/lexical_inline_yield_static_array.cr"
  printf 'PASS lexical inline yield with StaticArray union elements (%s)\n' "$compiler"
done
