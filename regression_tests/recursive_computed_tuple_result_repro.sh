#!/usr/bin/env bash
# A recursive tuple result can contain an integer computed by a settled call.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
safe="$root/scripts/run_safe.sh"
stock="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
fixture="$root/regression_tests/recursive_computed_tuple_result_repro.cr"
work="$(mktemp -d "${TMPDIR:-/tmp}/recursive-computed-tuple.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export RUN_SAFE_PASSTHROUGH_STDIO=1 CRYSTAL_CACHE_DIR="$work/cache"
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

sed 's/{output, end_index \&+ 1}/{output, "wrong"}/' "$fixture" > "$work/wrong_slot.cr"
sed 's/{output, end_index \&+ 1}/{output, Int32}/' "$fixture" > "$work/class_slot.cr"
sed 's/start \&+ 4/4_i64/' "$fixture" > "$work/wrong_helper.cr"
printf '6\n' > "$work/expected"

for mode in original lazy eager; do
  case "$mode" in
    original)
      build=("$safe" "$stock" 60 2048 build --prelude=empty "${link[@]}")
      ;;
    lazy)
      build=(env DEBUG_FORCE_LOWER_DEPTH=1 "$safe" "$candidate" 60 2048 --no-prelude --no-ast-cache --no-llvm-cache)
      ;;
    eager)
      build=(env ADAMAS_EAGER_MONO=1 "$safe" "$candidate" 60 2048 --no-prelude --no-ast-cache --no-llvm-cache)
      ;;
  esac

  "${build[@]}" "$fixture" -o "$work/$mode" > "$work/build.log" 2>&1 || { cat "$work/build.log" >&2; exit 1; }
  if [[ "$mode" == lazy ]]; then
    grep -E 'FORCE_LOWER_RECURSIVE_TUPLE.*RangeCycle#pieces.*RangeCycle#conditional' "$work/build.log" >/dev/null
  fi
  "$safe" "$work/$mode" 5 512 > "$work/actual" 2> "$work/run.log"
  cmp "$work/expected" "$work/actual"

  for invalid in wrong_slot class_slot wrong_helper; do
    case "$invalid" in
      wrong_slot) diagnostic='must return Tuple\(String, Int32\).*returning Tuple\(String, (Int32 \| )?String( \| Int32)?\)' ;;
      class_slot) diagnostic='must return Tuple\(String, Int32\).*returning Tuple\(String, (Int32 \| )?Int32.class( \| Int32)?\)|class.object.*Int32' ;;
      wrong_helper) diagnostic='must return Int32.*returning Int64' ;;
    esac
    if "${build[@]}" "$work/$invalid.cr" -o "$work/invalid" > "$work/invalid.log" 2>&1; then
      echo "$mode accepted $invalid" >&2
      exit 1
    fi
    grep -E "$diagnostic" "$work/invalid.log" >/dev/null || { cat "$work/invalid.log" >&2; exit 1; }
  done
  echo "$mode matched the computed recursive tuple and rejected invalid returns"
done
