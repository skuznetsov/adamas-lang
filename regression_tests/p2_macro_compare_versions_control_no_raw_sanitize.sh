#!/usr/bin/env bash
set -euo pipefail

compiler="${1:-bin/crystal_v2}"
tmpdir="$(mktemp -d /tmp/cv2_macro_compare_versions.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

{
  printf 'module MacroCompareGuard\n'
  printf '{%% if compare_versions(Crystal::VERSION, Crystal::VERSION) < 0 %%}\n'
  for i in $(seq 1 900); do
    printf '  OLD_%04d = %d\n' "$i" "$i"
  done
  printf '{%% end %%}\n'
  printf '{%% if compare_versions(Crystal::VERSION, Crystal::VERSION) == 0 %%}\n'
  printf '  NEW_SENTINEL = 1\n'
  printf '{%% end %%}\n'
  printf 'end\n'
} > "$tmpdir/repro.cr"

log="$tmpdir/repro.log"
DEBUG_CONST_LIT_WRITE=1 \
DEBUG_MACRO_STRIP_HOT=512 \
CRYSTAL_V2_STOP_AFTER_HIR=1 \
  scripts/run_safe.sh "$compiler" 20 1024 "$tmpdir/repro.cr" --no-prelude -o "$tmpdir/repro" \
  >"$log" 2>&1

if grep -q '\[MACRO_STRIP\]' "$log"; then
  echo "unexpected raw macro sanitizer on unresolved compare_versions control" >&2
  tail -80 "$log" >&2
  exit 1
fi

if grep -q 'MacroCompareGuard::OLD_' "$log"; then
  echo "inactive compare_versions branch was recorded" >&2
  tail -80 "$log" >&2
  exit 1
fi

grep -q 'MacroCompareGuard::NEW_SENTINEL' "$log"
echo "p2_macro_compare_versions_control_no_raw_sanitize_ok"
