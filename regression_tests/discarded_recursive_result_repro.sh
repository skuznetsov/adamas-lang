#!/usr/bin/env bash
# Lower a recursive call for its effects when an inline block ignores its value.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
safe="$root/scripts/run_safe.sh"
stock="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
work="$(mktemp -d /tmp/adamas-discarded-result.XXXXXX)"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

fixture="$root/regression_tests/discarded_recursive_result_repro.cr"
sed '/^  private def expand_accessor/,/^  end$/ {
  /^      visit(child)$/a\
      table.missing_accessor_member
}' "$fixture" > "$work/invalid.cr"
printf '53505\n' > "$work/expected"

for mode in original lazy eager; do
  case "$mode" in
    original) build=("$safe" "$stock" 60 2048 build --prelude=empty "${link[@]}") ;;
    lazy) build=("$safe" "$candidate" 60 2048 --no-prelude --no-ast-cache --no-llvm-cache) ;;
    eager) build=(env ADAMAS_EAGER_MONO=1 "$safe" "$candidate" 60 2048 --no-prelude --no-ast-cache --no-llvm-cache) ;;
  esac

  "${build[@]}" "$fixture" -o "$work/program" > "$work/build.log" 2>&1 || { cat "$work/build.log" >&2; exit 1; }
  "$safe" "$work/program" 5 512 > "$work/actual" 2> "$work/run.log" || { cat "$work/run.log" >&2; exit 1; }
  cmp "$work/expected" "$work/actual"

  if "${build[@]}" "$work/invalid.cr" -o "$work/invalid" > "$work/invalid.log" 2>&1; then
    echo "$mode accepted a missing method after the recursive call" >&2
    exit 1
  fi
  grep -Ei 'undefined method.*missing_accessor_member' "$work/invalid.log" >/dev/null || { cat "$work/invalid.log" >&2; exit 1; }
  echo "$mode preserved effects and result arms and checked the reachable tail"
done
