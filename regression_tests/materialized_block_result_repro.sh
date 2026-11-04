#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SOURCE="$ROOT/regression_tests/fixtures/materialized_block_result"
SAFE="$ROOT/scripts/run_safe.sh"
ADAMAS="${ADAMAS_BIN:-${1:-$ROOT/bin/adamas}}"
CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/adamas-materialized-block-result.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT

export CRYSTAL_CACHE_DIR="$WORK/cache"
export CRYSTAL_PATH="${CRYSTAL_PATH:-$(RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$CRYSTAL" 10 1024 env CRYSTAL_PATH)}"
if [[ "$(uname -s)" == Darwin ]]; then
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO

compile() {
  local compiler="$1" fixture="$2" output="$3"
  if [[ "$compiler" == stock ]]; then
    "$SAFE" "$CRYSTAL" 90 8192 build "$SOURCE/$fixture.cr" --no-debug -o "$output"
  else
    "$SAFE" "$ADAMAS" 90 8192 "$SOURCE/$fixture.cr" --no-debug --no-ast-cache --no-llvm-cache -o "$output"
  fi
}

for compiler in stock adamas; do
  output="$WORK/map.$compiler"
  if ! compile "$compiler" static_array_map "$output" >"$output.log" 2>&1; then
    cat "$output.log" >&2
    exit 1
  fi
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$output" 5 512 >"$output.stdout"

  output="$WORK/incompatible.$compiler"
  if compile "$compiler" incompatible "$output" >"$output.log" 2>&1; then
    printf 'Expected %s to reject the incompatible block result\n' "$compiler" >&2
    exit 1
  else
    code=$?
    if [[ "$code" != 1 ]]; then
      cat "$output.log" >&2
      exit 1
    fi
  fi
  if ! grep -Eq 'expected block.*to return.*, not Bool' "$output.log"; then
    cat "$output.log" >&2
    exit 1
  fi
done

diff -u "$WORK/map.stock.stdout" "$WORK/map.adamas.stdout"
printf 'PASS materialized block results (static array map and incompatible result)\n'
