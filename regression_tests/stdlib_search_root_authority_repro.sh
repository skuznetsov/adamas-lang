#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-stdlib-root.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
mkdir lib later
printf 'LIB_VALUE = 7\n' > lib/root_authority_probe.cr
printf 'LIB_VALUE = 9\n' > later/root_authority_probe.cr
printf 'require "root_authority_probe"\nputs LIB_VALUE\n' > hello.cr

stock_path="$(env -u CRYSTAL_PATH "$original" env CRYSTAL_PATH)"
# Keep the stock leading project root and insert a second project root after
# it. Both compilers must still resolve the same require before using stdlib.
export CRYSTAL_PATH="${stock_path%%:*}:$work/later:${stock_path#*:}"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

compile() {
  local log="$1"
  shift
  if ! "$@" > "$log" 2>&1; then
    cat "$log" >&2
    exit 1
  fi
}

compile original.log "$safe" "$original" 120 8192 build hello.cr --no-debug \
  "${original_flags[@]}" -o original
compile candidate.log "$safe" "$candidate" 120 8192 hello.cr --no-debug \
  --no-ast-cache --no-llvm-cache -o candidate
"$safe" "$work/original" 5 512 > original.out
"$safe" "$work/candidate" 5 512 > candidate.out
printf '7\n' | diff -u - original.out
diff -u original.out candidate.out
printf 'PASS stock Crystal search path and ordered project requires\n'
