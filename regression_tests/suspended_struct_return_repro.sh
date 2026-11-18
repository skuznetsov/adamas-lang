#!/usr/bin/env bash
# A typed early return anchors a recursive cycle reached through forwarding calls.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
safe="$root/scripts/run_safe.sh"
stock="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
fixture="$root/regression_tests/suspended_struct_return_repro.cr"
work="$(mktemp -d "${TMPDIR:-/tmp}/suspended-struct.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export RUN_SAFE_PASSTHROUGH_STDIO=1 CRYSTAL_CACHE_DIR="$work/cache"
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi
printf 'RRAA\n' > "$work/expected"
sed 's/return sections.first/return 13/' "$fixture" > "$work/bad-result.cr"
sed 's/new(true, true)/new(7, true)/' "$fixture" > "$work/bad-argument.cr"
for mode in stock candidate; do
  if [[ "$mode" == stock ]]; then
    build=("$safe" "$stock" 60 2048 build --prelude=empty "${link[@]}")
  else
    build=("$safe" "$candidate" 60 2048 --no-prelude --no-ast-cache --no-llvm-cache)
  fi
  "${build[@]}" "$fixture" -o "$work/bin" > "$work/build.log" 2>&1 || { cat "$work/build.log" >&2; exit 1; }
  "$safe" "$work/bin" 6 512 > "$work/output" 2> "$work/run.log" || { cat "$work/run.log" >&2; exit 1; }
  cmp "$work/expected" "$work/output"
  for negative in bad-result bad-argument; do
    if "${build[@]}" "$work/$negative.cr" -o "$work/invalid" > "$work/reject.log" 2>&1; then
      echo "$mode accepted $negative" >&2
      exit 1
    fi
    case "$negative" in
      bad-result) pattern='ResultIndex.*Int32|Int32.*ResultIndex' ;;
      bad-argument) pattern='Bool.*Int32|Int32.*Bool' ;;
    esac
    grep -Eq "$pattern" "$work/reject.log" || { cat "$work/reject.log" >&2; exit 1; }
  done
  echo "$mode matched the recursive calls and rejected the invalid return and argument"
done
