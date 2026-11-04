#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:?usage: $0 /path/to/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
fixtures="$root/regression_tests/named_tuple_receiver_union"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-named-tuple-receiver-union.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache"

if [[ -z "${CRYSTAL_PATH:-}" ]]; then
  export CRYSTAL_PATH="$("$safe" "$original" 10 512 env CRYSTAL_PATH 2>"$work/crystal-path.log" |
    sed -n '/^=== STDOUT ===$/,/^=== STDERR ===$/{ /^=== /d; p; }')"
fi
test -n "$CRYSTAL_PATH"

stock_link=()
if [[ "$(uname -s)" == Darwin ]]; then
  stock_link=(--link-flags=-fuse-ld=/usr/bin/ld)
fi

check() {
  local producer="$1" name="$2" prelude="$3" diagnostic="${4:-}"
  local prefix="$work/$producer.$name"
  local status=0
  local command=()
  local flags=()

  if [[ "$producer" == crystal ]]; then
    [[ "$prelude" != empty ]] || flags=(--prelude=empty)
    command=("$original" 90 4096 build --no-color "${stock_link[@]}")
  else
    [[ "$prelude" != empty ]] || flags=(--no-prelude)
    command=("$candidate" 120 8192 --no-ast-cache --no-llvm-cache)
  fi

  cp "$fixtures/$name.cr" "$work/$name.cr"
  "$safe" "${command[@]}" "${flags[@]}" --no-debug "$work/$name.cr" -o "$prefix" >"$prefix.compile.log" 2>&1 || status=$?
  if [[ -n "$diagnostic" ]]; then
    if [[ "$status" != 1 ]] || ! grep -Eq "^[Ee]rror: $diagnostic" "$prefix.compile.log"; then
      cat "$prefix.compile.log" >&2
      return 1
    fi
  else
    if [[ "$status" != 0 ]] || ! grep -Fq '[EXIT: 0]' "$prefix.compile.log"; then
      cat "$prefix.compile.log" >&2
      return 1
    fi
    if ! "$safe" "$prefix" 5 512 >"$prefix.run.log" 2>&1 || ! grep -Fq '[EXIT: 0]' "$prefix.run.log"; then
      cat "$prefix.run.log" >&2
      return 1
    fi
    sed -n '/^=== STDOUT ===$/,/^=== STDERR ===$/{ /^=== /d; p; }' "$prefix.run.log" >"$prefix.stdout"
  fi
  printf 'PASS[%s] %s\n' "$producer" "$name"
}

for producer in crystal adamas; do
  check "$producer" return_abi empty
  check "$producer" evaluate_argument_once empty
  check "$producer" reject_wrong_argument empty '.*#select.*NamedTuple\(other: Int64\).*NamedTuple\(value: Int32\)'
  check "$producer" reject_private empty "private method 'hidden'"
  check "$producer" stdlib_dynamic_lookup installed
done
diff -u "$work/crystal.stdlib_dynamic_lookup.stdout" "$work/adamas.stdlib_dynamic_lookup.stdout"
