#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
safe="$root/scripts/run_safe.sh"
stock="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
fixtures="$root/regression_tests/fixtures/unannotated_captured_literal"
work="$(mktemp -d "${TMPDIR:-/tmp}/unannotated-captured-literal.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

printf 'ABC\n' > "$work/expected"
for mode in stock candidate; do
  if [[ "$mode" == stock ]]; then
    build=("$safe" "$stock" 60 2048 build --prelude=empty "${link[@]}")
  else
    build=("$safe" "$candidate" 60 2048 --no-prelude --no-ast-cache --no-llvm-cache)
  fi
  "${build[@]}" "$fixtures/valid.cr" -o "$work/program" > "$work/build.log" 2>&1 ||
    { cat "$work/build.log" >&2; exit 1; }
  "$safe" "$work/program" 5 512 > "$work/stdout" 2> "$work/run.log" ||
    { cat "$work/run.log" >&2; exit 1; }
  cmp "$work/expected" "$work/stdout"

  for invalid in wrong_arity wrong_actual wrong_body; do
    status=0
    "${build[@]}" "$fixtures/$invalid.cr" -o "$work/$invalid" > "$work/build.log" 2>&1 || status=$?
    if [[ "$status" != 1 || -e "$work/$invalid" ]]; then
      echo "$mode gave unexpected exit $status for $invalid" >&2
      cat "$work/build.log" >&2
      exit 1
    fi
    case "$invalid" in
      wrong_arity) diagnostic='block parameters.*given 1.*expected (maximum )?0' ;;
      wrong_actual) diagnostic='(expected argument|no overload matches).*(Int32|String)' ;;
      wrong_body) diagnostic='undefined (local variable or )?method.*unknown_callback_operation' ;;
    esac
    grep -Eq "$diagnostic" "$work/build.log" || { cat "$work/build.log" >&2; exit 1; }
  done
  echo "$mode passed named callback capture and strict rejection controls"
done
