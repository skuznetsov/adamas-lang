#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SOURCE="$ROOT/regression_tests/fixtures/concrete_union_dispatch"
SAFE="$ROOT/scripts/run_safe.sh"
ADAMAS="${ADAMAS_BIN:-${1:-$ROOT/bin/adamas}}"
CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/adamas-concrete-union-dispatch.XXXXXX")"
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

for fixture in results inherited; do
  for compiler in stock adamas; do
    output="$WORK/$fixture.$compiler"
    if ! compile "$compiler" "$fixture" "$output" >"$output.log" 2>&1; then
      cat "$output.log" >&2
      exit 1
    fi
    RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$output" 5 512 >"$output.small"
    RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$output" 5 512 wide >"$output.wide"
  done
  diff -u "$WORK/$fixture.stock.small" "$WORK/$fixture.adamas.small"
  diff -u "$WORK/$fixture.stock.wide" "$WORK/$fixture.adamas.wide"
  printf 'PASS concrete union dispatch (%s)\n' "$fixture"
done

for compiler in stock adamas; do
  output="$WORK/missing.$compiler"
  if compile "$compiler" missing "$output" >"$output.log" 2>&1; then
    printf 'Expected %s to reject the missing union arm\n' "$compiler" >&2
    exit 1
  else
    code=$?
    if [[ "$code" != 1 ]]; then
      cat "$output.log" >&2
      exit 1
    fi
  fi
  if ! grep -Eq "wrong number of arguments.*UnavailableKey#key|no overload matches UnavailableKey#key" "$output.log"; then
    cat "$output.log" >&2
    exit 1
  fi
done
printf 'PASS concrete union dispatch (missing overload)\n'
