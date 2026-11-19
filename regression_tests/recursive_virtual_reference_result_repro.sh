#!/usr/bin/env bash
# A reachable instance join can close a recursive result obligation.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
safe="$root/scripts/run_safe.sh"
stock="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
fixture="$root/regression_tests/recursive_virtual_reference_result_repro.cr"
work="$(mktemp -d "${TMPDIR:-/tmp}/recursive-reference.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi
sed 's/^    FirstResult\.new$/    17/' "$fixture" > "$work/wrong_type.cr"
sed 's/^    FirstResult\.new$/    FirstResult/' "$fixture" > "$work/class_object.cr"
sed 's/^abstract class ParseResult$/abstract class ParseResult < Object/' "$fixture" > "$work/shallow_root.cr"
printf 'AB\n' > "$work/expected"
for mode in stock candidate; do
  if [[ "$mode" == stock ]]; then
    build=("$safe" "$stock" 60 2048 build --prelude=empty "${link[@]}")
  else
    build=("$safe" "$candidate" 60 2048 --no-prelude --no-ast-cache --no-llvm-cache)
  fi
  "${build[@]}" "$fixture" -o "$work/$mode" > "$work/build.log" 2>&1 || { cat "$work/build.log" >&2; exit 1; }
  "$safe" "$work/$mode" 5 512 > "$work/$mode.out" 2> "$work/run.log" || { cat "$work/run.log" >&2; exit 1; }
  cmp "$work/expected" "$work/$mode.out"
  for invalid in wrong_type class_object; do
    if "${build[@]}" "$work/$invalid.cr" -o "$work/invalid" > "$work/invalid.log" 2>&1; then
      echo "$mode accepted $invalid as an instance of ParseResult" >&2
      exit 1
    fi
    if [[ "$invalid" == wrong_type ]]; then
      grep -E 'ParseResult.*Int32|Int32.*ParseResult' "$work/invalid.log" >/dev/null || { cat "$work/invalid.log" >&2; exit 1; }
    else
      grep -E 'ParseResult.*FirstResult\.class|FirstResult\.class.*ParseResult' "$work/invalid.log" >/dev/null || { cat "$work/invalid.log" >&2; exit 1; }
    fi
  done
  echo "$mode matched the recursive virtual reference results and rejected both invalid branches"
done

# Crystal retains the union of the sibling classes for a depth-one root.
# Such a pair cannot authorize the virtual-root proof. A compiler with a
# separate tagged result proof may still complete this valid program.
"$safe" "$stock" 60 2048 build --prelude=empty "${link[@]}" "$work/shallow_root.cr" -o "$work/shallow-stock" > "$work/build.log" 2>&1 || { cat "$work/build.log" >&2; exit 1; }
"$safe" "$work/shallow-stock" 5 512 > "$work/shallow-stock.out" 2> "$work/run.log" || { cat "$work/run.log" >&2; exit 1; }
cmp "$work/expected" "$work/shallow-stock.out"
if DEBUG_FORCE_LOWER_DEPTH=1 "$safe" "$candidate" 60 2048 --no-prelude --no-ast-cache --no-llvm-cache "$work/shallow_root.cr" -o "$work/shallow-candidate" > "$work/shallow.log" 2>&1; then
  "$safe" "$work/shallow-candidate" 5 512 > "$work/shallow-candidate.out" 2> "$work/run.log" || { cat "$work/run.log" >&2; exit 1; }
  cmp "$work/shallow-stock.out" "$work/shallow-candidate.out"
else
  grep -E 'pending source result Reader#' "$work/shallow.log" >/dev/null || { cat "$work/shallow.log" >&2; exit 1; }
fi
if grep -F '[FORCE_LOWER_RECURSIVE_REFERENCE]' "$work/shallow.log"; then
  echo "candidate opened a virtual result for a depth-one root" >&2
  exit 1
fi
echo "candidate reserved the virtual reference proof for eligible Crystal roots"
