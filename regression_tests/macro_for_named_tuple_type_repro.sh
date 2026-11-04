#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:?usage: $0 /path/to/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
fixture="$root/regression_tests/fixtures/macro_for_named_tuple_type.cr"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-macro-for-named-tuple-type.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cp "$fixture" "$work/probe.cr"
export CRYSTAL_CACHE_DIR="$work/cache"

stock_link=()
if [[ "$(uname -s)" == Darwin ]]; then
  stock_link=(--link-flags=-fuse-ld=/usr/bin/ld)
fi

check() {
  local name="$1"
  shift
  if ! "$safe" "$@" -o "$work/$name" >"$work/$name.compile.log" 2>&1; then
    cat "$work/$name.compile.log" >&2
    return 1
  fi
  if ! "$safe" "$work/$name" 5 512 >"$work/$name.run.log" 2>&1; then
    cat "$work/$name.run.log" >&2
    return 1
  fi
  grep -Fq '[EXIT: 0]' "$work/$name.run.log"
  printf 'PASS[%s] NamedTuple type key, value, and index bindings\n' "$name"
}

check crystal "$original" 60 4096 build "$work/probe.cr" --prelude=empty --no-debug --no-color "${stock_link[@]}"
check adamas "$candidate" 90 8192 "$work/probe.cr" --no-prelude --no-debug --no-ast-cache --no-llvm-cache
