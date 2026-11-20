#!/usr/bin/env bash
# A blockless recursive replay cannot inherit its caller's callback result.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
safe="$root/scripts/run_safe.sh"
stock="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
work="$(mktemp -d "${TMPDIR:-/tmp}/recursive-callback-scope.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

fixture="$root/regression_tests/fixtures/recursive_callback_scope.cr"
printf 'callback\nA\ncallback\nA\nN\nalternate\nB\nalternate\nB\ncallback\nA\n' > "$work/expected"
sed 's/"A" # callback result/false/' "$fixture" > "$work/wrong_callback.cr"
sed 's/"N" # later method result/false/' "$fixture" > "$work/wrong_return.cr"

for mode in original lazy eager; do
  case "$mode" in
    original) build=("$safe" "$stock" 60 2048 build --prelude=empty "${link[@]}") ;;
    lazy) build=("$safe" "$candidate" 60 2048 --no-prelude --no-ast-cache --no-llvm-cache) ;;
    eager) build=(env ADAMAS_EAGER_MONO=1 "$safe" "$candidate" 60 2048 --no-prelude --no-ast-cache --no-llvm-cache) ;;
  esac
  binary="$work/$mode"
  "${build[@]}" "$fixture" -o "$binary" > "$work/build.log" 2>&1 || { cat "$work/build.log" >&2; exit 1; }
  "$safe" "$binary" 5 512 > "$work/out" 2> "$work/run.log" || { cat "$work/run.log" >&2; exit 1; }
  cmp "$work/expected" "$work/out"
  for invalid in wrong_callback wrong_return; do
    if "${build[@]}" "$work/$invalid.cr" -o "$work/invalid" > "$work/invalid.log" 2>&1; then
      echo "$mode accepted $invalid" >&2
      exit 1
    fi
    test ! -e "$work/invalid"
    case "$invalid" in
      wrong_callback) diagnostic='expected block.*return String, not Bool' ;;
      wrong_return) diagnostic='evaluate_expression.*must return String.*Bool' ;;
    esac
    grep -E "$diagnostic" "$work/invalid.log" >/dev/null || { cat "$work/invalid.log" >&2; exit 1; }
  done
  echo "$mode matched both block bodies and rejected the invalid callback and method return"
done
