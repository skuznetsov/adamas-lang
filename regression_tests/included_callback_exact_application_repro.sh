#!/usr/bin/env bash
# The receiver and included module spell their independent type formals T.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
safe="$root/scripts/run_safe.sh"
stock="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
fixture="$root/regression_tests/fixtures/included_callback_exact_application.cr"
work="$(mktemp -d "${TMPDIR:-/tmp}/included-callback.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT

export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

sed 's/tuple_tag(receiver.map/number_tag(receiver.map/' "$fixture" > "$work/wrong_tuple.cr"
sed 's/class_tag(receiver.map/number_tag(receiver.map/' "$fixture" > "$work/wrong_kind.cr"
printf 'ABC\n' > "$work/expected"

for mode in stock lazy eager; do
  if [[ "$mode" == stock ]]; then
    build=("$safe" "$stock" 60 2048 build --prelude=empty "${link[@]}")
  else
    build=("$safe" "$candidate" 60 2048 --no-prelude --no-ast-cache --no-llvm-cache)
    if [[ "$mode" == eager ]]; then
      build=(env ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1 "${build[@]}")
    fi
  fi

  "${build[@]}" "$fixture" -o "$work/$mode" > "$work/build.log" 2>&1 || { cat "$work/build.log" >&2; exit 1; }
  "$safe" "$work/$mode" 5 512 > "$work/$mode.out" 2> "$work/run.log" || { cat "$work/run.log" >&2; exit 1; }
  diff -u "$work/expected" "$work/$mode.out"

  for case_name in wrong_tuple wrong_kind; do
    status=0
    "${build[@]}" "$work/$case_name.cr" -o "$work/invalid" > "$work/invalid.log" 2>&1 || status=$?
    if [[ "$status" != 1 || -e "$work/invalid" ]]; then
      cat "$work/invalid.log" >&2
      echo "$mode failed to reject $case_name" >&2
      exit 1
    fi
  done
  echo "$mode used the selected include's callback types and rejected incompatible results"
done
