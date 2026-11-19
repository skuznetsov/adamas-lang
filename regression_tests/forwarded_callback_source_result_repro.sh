#!/usr/bin/env bash
# A lexical forwarding call supplies its own source result before specialization.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
safe="$root/scripts/run_safe.sh"
stock="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
fixture="$root/regression_tests/forwarded_callback_source_result_repro.cr"
work="$(mktemp -d "${TMPDIR:-/tmp}/forwarded-callback.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi
sed 's/class_tag(forward_again/instance_tag(forward_again/' "$fixture" > "$work/wrong_kind.cr"
printf 'ABA\n' > "$work/expected"
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
  status=0
  "${build[@]}" "$work/wrong_kind.cr" -o "$work/invalid" > "$work/invalid.log" 2>&1 || status=$?
  if [[ "$status" != 1 || -e "$work/invalid" ]] ||
     ! grep -Eq 'instance_tag.*ResultBox\(Int32\.class\)|ResultBox\(Int32\.class\).*instance_tag' "$work/invalid.log"; then
    cat "$work/invalid.log" >&2
    echo "$mode failed to reject the crossed callback result kind" >&2
    exit 1
  fi
  echo "$mode matched the forwarded results and rejected the crossed result kind"
done
