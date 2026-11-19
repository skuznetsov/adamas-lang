#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
safe="$root/scripts/run_safe.sh"
stock="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
fixtures=(
  "$root/regression_tests/fixtures/defaulted_recursive_struct_result.cr"
  "$root/regression_tests/fixtures/checked_call_recursive_struct_result.cr"
  "$root/regression_tests/fixtures/nullable_recursive_struct_result.cr"
)
work="$(mktemp -d "${TMPDIR:-/tmp}/defaulted-recursive-struct.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

for mode in stock candidate; do
  if [[ "$mode" == stock ]]; then
    build=("$safe" "$stock" 60 2048 build --prelude=empty "${link[@]}")
  else
    build=("$safe" "$candidate" 60 2048 --no-prelude --no-ast-cache --no-llvm-cache)
  fi
  for fixture in "${fixtures[@]}"; do
    sed 's/^      parse0$/      parse0(false)/' "$fixture" > "$work/positional.cr"
    sed 's/RecCode.new(69)/69/' "$fixture" > "$work/wrong-return.cr"
    sed 's/    parse0(again)/    parse0(Bool)/' "$fixture" > "$work/wrong-kind.cr"
    sources=("$fixture" "$work/positional.cr")
    if [[ "$fixture" == */nullable_recursive_struct_result.cr ]]; then
      printf 'ABWN\n' > "$work/expected"
      sed -e '/^parser.checked_zero$/d' -e 's/return checked_zero unless/return RecCode.new(65) unless/' \
        "$fixture" > "$work/allocator.cr"
      sources+=("$work/allocator.cr")
    else
      printf 'AB\n' > "$work/expected"
    fi
    for source in "${sources[@]}"; do
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
        wrong-return) diagnostic='must return .*RecCode.*Int32' ;;
        wrong-kind)   diagnostic='expected argument.*Bool' ;;
      esac
      grep -Eq "$diagnostic" "$work/build.log" || { cat "$work/build.log" >&2; exit 1; }
    done
  done
  echo "$mode passed the recursive constant, direct-call, and tagged return controls"
done
