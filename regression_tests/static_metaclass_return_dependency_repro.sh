#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$root/regression_tests/fixtures/static_metaclass_return_dependency"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-static-metaclass-return.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
export CRYSTAL_PATH="${CRYSTAL_PATH:-$(env -u CRYSTAL_PATH "$original" env CRYSTAL_PATH)}"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_link_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_link_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

check_case() {
  local name="$1" expected="$2"
  local original_flags=() candidate_flags=()
  if [[ "$name" == replay ]]; then
    original_flags=(--prelude=empty)
    candidate_flags=(--no-prelude)
  fi

  "$safe" "$original" 90 8192 build "$fixture/$name.cr" --single-module --no-debug \
    "${original_link_flags[@]}" "${original_flags[@]}" -o "$name.original" > "$name.original.log" 2>&1 ||
    { cat "$name.original.log" >&2; return 1; }
  "$safe" "$work/$name.original" 5 512 > "$name.original.out"
  printf '%s' "$expected" | diff -u - "$name.original.out"

  "$safe" "$candidate" 90 8192 "$fixture/$name.cr" --no-debug --no-ast-cache --no-llvm-cache \
    "${candidate_flags[@]}" -o "$name.candidate" > "$name.candidate.log" 2>&1 ||
    { cat "$name.candidate.log" >&2; return 1; }
  "$safe" "$work/$name.candidate" 5 512 > "$name.candidate.out"
  diff -u "$name.original.out" "$name.candidate.out"
  printf 'PASS %s\n' "$name"
}

# Two specializations and a repeated call must preserve the class-object kind.
check_case replay ACA
# The unseeded sum must carry the inherited : self result into the loop phi.
check_case enumerable_sum AB
