#!/usr/bin/env bash
# The cycle needs the exact struct result and still must check every callee body.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
safe="$root/scripts/run_safe.sh"
stock="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
fixture="$root/regression_tests/recursive_struct_result_repro.cr"
work="$(mktemp -d "${TMPDIR:-/tmp}/recursive-struct.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi
sed 's/RecCode.new(69)/69/' "$fixture" > "$work/invalid.cr"
printf 'AB\n' > "$work/expected"
for mode in stock candidate; do
  if [[ "$mode" == stock ]]; then
    build=("$safe" "$stock" 60 2048 build --prelude=empty "${link[@]}")
  else
    build=("$safe" "$candidate" 60 2048 --no-prelude --no-ast-cache --no-llvm-cache)
  fi
  "${build[@]}" "$fixture" -o "$work/$mode" > "$work/build.log" 2>&1 || { cat "$work/build.log" >&2; exit 1; }
  "$safe" "$work/$mode" 5 512 > "$work/$mode.out" 2> "$work/run.log" || { cat "$work/run.log" >&2; exit 1; }
  cmp "$work/expected" "$work/$mode.out"
  if "${build[@]}" "$work/invalid.cr" -o "$work/invalid" > "$work/invalid.log" 2>&1; then
    echo "$mode accepted an incompatible return from parse4" >&2
    exit 1
  fi
  grep -E 'RecCode.*Int32|Int32.*RecCode' "$work/invalid.log" || { cat "$work/invalid.log" >&2; exit 1; }
  echo "$mode passed the recursive struct result and invalid-body controls"
done
