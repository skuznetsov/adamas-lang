#!/usr/bin/env bash
# A selected String index overload owns its result type.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
safe="$root/scripts/run_safe.sh"
stock="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
fixtures="$root/regression_tests/fixtures"
run="$(mktemp -d "${TMPDIR:-/tmp}/string-index-result.XXXXXX")"
trap 'rm -rf -- "$run"' EXIT

export CRYSTAL_CACHE_DIR="$run/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

sed 's/bool_code(text\[TextIndex.new\])/char_code(text[TextIndex.new])/' \
  "$fixtures/string_source_index_overloads.cr" > "$run/wrong_result.cr"
printf 'ABC\n' > "$run/expected"

for mode in stock lazy eager; do
  if [[ "$mode" == stock ]]; then
    build=("$safe" "$stock" 60 2048 build --prelude=empty "${link[@]}")
  else
    build=("$safe" "$candidate" 60 2048 --no-prelude --no-ast-cache --no-llvm-cache)
    if [[ "$mode" == eager ]]; then
      build=(env ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1 "${build[@]}")
    fi
  fi

  "${build[@]}" "$fixtures/string_source_index_overloads.cr" \
    -o "$run/overloads" >"$run/build.log" 2>&1 || { cat "$run/build.log" >&2; exit 1; }
  "$safe" "$run/overloads" 5 512 >"$run/overloads.out" 2>"$run/runtime.log" \
    || { cat "$run/runtime.log" >&2; exit 1; }
  diff -u "$run/expected" "$run/overloads.out"

  status=0
  "${build[@]}" "$run/wrong_result.cr" -o "$run/invalid" \
    >"$run/invalid.log" 2>&1 || status=$?
  if [[ "$status" != 1 || -e "$run/invalid" ]] || ! grep -q 'expected argument.*Char.*Bool' "$run/invalid.log"; then
    cat "$run/invalid.log" >&2
    echo "$mode failed to reject the wrong restriction for the selected index result" >&2
    exit 1
  fi

  echo "$mode retained the selected String index result and checked its restriction"
done
