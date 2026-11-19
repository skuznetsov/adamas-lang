#!/usr/bin/env bash
# An exact recursive result can be established by a reachable literal return.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
safe="$root/scripts/run_safe.sh"
stock="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
work="$(mktemp -d "${TMPDIR:-/tmp}/recursive-literal.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

bool_fixture="$root/regression_tests/recursive_literal_bool_result_repro.cr"
string_fixture="$root/regression_tests/recursive_literal_string_result_repro.cr"
printf 'AZ\n' > "$work/bool.expected"
printf 'A\nZ\n' > "$work/string.expected"
# Keep the recursive call and a valid reached return. The final body still
# has to reject the wrong kind or type in a later branch.
awk '{print} $0 == "    evaluate_text(depth &- 1) == 65" {print "    Bool"}' "$bool_fixture" > "$work/wrong_kind.cr"
sed 's/flag(depth) ? "A" : "C"/flag(depth) ? "A" : 17/' "$string_fixture" > "$work/wrong_type.cr"

for mode in original lazy eager; do
  case "$mode" in
    original) build=("$safe" "$stock" 60 2048 build --prelude=empty "${link[@]}") ;;
    lazy) build=("$safe" "$candidate" 60 2048 --no-prelude --no-ast-cache --no-llvm-cache) ;;
    eager) build=(env ADAMAS_EAGER_MONO=1 "$safe" "$candidate" 60 2048 --no-prelude --no-ast-cache --no-llvm-cache) ;;
  esac
  for kind in bool string; do
    if [[ "$kind" == bool ]]; then fixture="$bool_fixture"; else fixture="$string_fixture"; fi
    "${build[@]}" "$fixture" -o "$work/positive" > "$work/build.log" 2>&1 || { cat "$work/build.log" >&2; exit 1; }
    "$safe" "$work/positive" 5 512 > "$work/positive.out" 2> "$work/run.log" || { cat "$work/run.log" >&2; exit 1; }
    cmp "$work/$kind.expected" "$work/positive.out"
  done
  for invalid in wrong_kind wrong_type; do
    if "${build[@]}" "$work/$invalid.cr" -o "$work/invalid" > "$work/invalid.log" 2>&1; then
      echo "$mode accepted $invalid" >&2
      exit 1
    fi
    if [[ "$invalid" == wrong_kind ]]; then
      grep -E 'Bool.*Bool\.class|Bool\.class.*Bool' "$work/invalid.log" >/dev/null || { cat "$work/invalid.log" >&2; exit 1; }
    else
      grep -E 'String.*Int32|Int32.*String' "$work/invalid.log" >/dev/null || { cat "$work/invalid.log" >&2; exit 1; }
    fi
  done
  echo "$mode matched the recursive Bool and String results and rejected invalid result type and kind"
done
