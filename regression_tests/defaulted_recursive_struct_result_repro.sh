#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
safe="$root/scripts/run_safe.sh"
stock="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
fixture="$root/regression_tests/fixtures/defaulted_recursive_struct_result.cr"
work="$(mktemp -d "${TMPDIR:-/tmp}/defaulted-recursive-struct.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

sed 's/^      parse0$/      parse0(false)/' "$fixture" > "$work/positional.cr"
sed 's/RecCode.new(69)/69/' "$fixture" > "$work/wrong-return.cr"
sed 's/    parse0(again)/    parse0(Bool)/' "$fixture" > "$work/wrong-kind.cr"
printf 'AB\n' > "$work/expected"
for mode in stock candidate; do
  if [[ "$mode" == stock ]]; then
    build=("$safe" "$stock" 60 2048 build --prelude=empty "${link[@]}")
  else
    build=("$safe" "$candidate" 60 2048 --no-prelude --no-ast-cache --no-llvm-cache)
  fi
  for source in "$fixture" "$work/positional.cr"; do
    "${build[@]}" "$source" -o "$work/program" > "$work/build.log" 2>&1 ||
      { cat "$work/build.log" >&2; exit 1; }
    "$safe" "$work/program" 5 512 > "$work/stdout" 2> "$work/run.log" ||
      { cat "$work/run.log" >&2; exit 1; }
    cmp "$work/expected" "$work/stdout"
  done
  for invalid in wrong-return wrong-kind; do
    if "${build[@]}" "$work/$invalid.cr" -o "$work/$invalid" > "$work/build.log" 2>&1 ||
       [[ -e "$work/$invalid" ]]; then
      echo "$mode accepted $invalid" >&2
      exit 1
    fi
    case "$invalid" in
      wrong-return) diagnostic='must return RecCode.*Int32' ;;
      wrong-kind)   diagnostic='expected argument.*Bool' ;;
    esac
    grep -Eq "$diagnostic" "$work/build.log" || { cat "$work/build.log" >&2; exit 1; }
  done
  echo "$mode passed the recursive default and invalid-source controls"
done
