#!/usr/bin/env bash
# An ordinary CallStack use must finish the pending DWARF and cache methods.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
safe="$root/scripts/run_safe.sh"
original="${ORIGINAL_CRYSTAL_BIN:-${CRYSTAL_BIN:-$(command -v crystal)}}"
candidate="${ADAMAS_BIN:-${1:-$root/bin/adamas}}"
fixture="$root/regression_tests/callstack_pending_retry_repro.cr"
work="$(mktemp -d "${TMPDIR:-/tmp}/callstack-pending-retry.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export RUN_SAFE_PASSTHROUGH_STDIO=1
export CRYSTAL_PATH="${ORIGINAL_CRYSTAL_PATH:-$(env -u CRYSTAL_PATH "$original" env CRYSTAL_PATH)}"
printf 'empty-callstack\n' > "$work/expected"

for mode in original candidate; do
  if [[ "$mode" == original ]]; then
    compiler=("$original" 180 4096 build)
    if [[ "$(uname -s)" == Darwin ]]; then
      compiler+=(--link-flags=-fuse-ld=/usr/bin/ld)
    fi
  else
    compiler=("$candidate" 180 4096 --no-ast-cache --no-llvm-cache)
  fi
  "$safe" "${compiler[@]}" "$fixture" -o "$work/$mode" > "$work/build.log" 2>&1 || { cat "$work/build.log" >&2; exit 1; }
  "$safe" "$work/$mode" 5 512 > "$work/$mode.out" 2> "$work/run.log" || { cat "$work/run.log" >&2; exit 1; }
  cmp "$work/expected" "$work/$mode.out"
done
echo "PASS CallStack lookup on the installed Crystal stdlib"
