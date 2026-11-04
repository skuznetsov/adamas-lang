#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SOURCE="$ROOT/regression_tests/fixtures/constructor_projection_identity"
SAFE="$ROOT/scripts/run_safe.sh"
ADAMAS="${ADAMAS_BIN:-${1:-$ROOT/bin/adamas}}"
CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/adamas-constructor-projection-identity.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT

export CRYSTAL_CACHE_DIR="$WORK/cache"
export CRYSTAL_PATH="${CRYSTAL_PATH:-$(RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$CRYSTAL" 10 1024 env CRYSTAL_PATH)}"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO

compile() {
  local compiler="$1" fixture="$2" output="$3"
  if [[ "$compiler" == stock ]]; then
    "$SAFE" "$CRYSTAL" 20 2048 build --prelude=empty --no-debug "$SOURCE/$fixture.cr" -o "$output"
  else
    local eager=0
    if [[ "$compiler" == eager ]]; then eager=1; fi
    ADAMAS_EAGER_HIR="$eager" "$SAFE" "$ADAMAS" 20 2048 --no-prelude --no-debug --no-ast-cache --no-llvm-cache "$SOURCE/$fixture.cr" -o "$output"
  fi
}

for compiler in stock lazy eager; do
  for fixture in included_self lexical source_direct source_transitive; do
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

  output="$WORK/conflict.$compiler"
  code=0
  compile "$compiler" conflict "$output" >"$output.log" 2>&1 || code=$?
  if [[ "$code" != 1 ]] || ! grep -Eiq 'cannot infer|no overload matches|expected argument|already set' "$output.log"; then
    cat "$output.log" >&2
    exit 1
  fi
  printf 'PASS constructor projection identity (%s)\n' "$compiler"
done
