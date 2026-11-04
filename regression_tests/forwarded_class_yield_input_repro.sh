#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
FIXTURES="$ROOT/regression_tests/fixtures/forwarded_class_yield_input"
SAFE="$ROOT/scripts/run_safe.sh"
ADAMAS="${ADAMAS_BIN:-${1:-$ROOT/bin/adamas}}"
CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/adamas-forwarded-class-yield-input.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT

export CRYSTAL_CACHE_DIR="$WORK/cache"
export CRYSTAL_PATH="${CRYSTAL_PATH:-$(RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$CRYSTAL" 10 1024 env CRYSTAL_PATH)}"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO

cp "$FIXTURES/standalone_callback.cr" "$WORK/standalone_callback.cr"
cp "$FIXTURES/implicit_receiver.cr" "$WORK/implicit_receiver.cr"
sed 's/    open_internal(value)/    self.open_internal(value)/' "$FIXTURES/standalone_callback.cr" >"$WORK/explicit_receiver.cr"
sed 's/read(resource) == 2147483649_i64/read_number(resource) == 19_i32/' "$FIXTURES/implicit_receiver.cr" >"$WORK/wrong_consumer.cr"

compile() {
  local compiler="$1" fixture="$2" output="$3"
  if [[ "$compiler" == stock ]]; then
    "$SAFE" "$CRYSTAL" 20 2048 build --prelude=empty --no-debug "$WORK/$fixture.cr" -o "$output"
  else
    local eager=0
    if [[ "$compiler" == eager ]]; then eager=1; fi
    ADAMAS_EAGER_HIR="$eager" "$SAFE" "$ADAMAS" 20 2048 --no-prelude --no-debug --no-ast-cache --no-llvm-cache "$WORK/$fixture.cr" -o "$output"
  fi
}

for compiler in stock lazy eager; do
  for fixture in standalone_callback explicit_receiver implicit_receiver; do
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

  output="$WORK/wrong_consumer.$compiler"
  code=0
  compile "$compiler" wrong_consumer "$output" >"$output.log" 2>&1 || code=$?
  if [[ "$code" != 1 ]] || ! grep -Eiq '(no overload matches read_number.*Resource|read_number.*to be Int32, not Resource)' "$output.log"; then
    cat "$output.log" >&2
    exit 1
  fi
  printf 'PASS forwarded class yield input (%s)\n' "$compiler"
done
