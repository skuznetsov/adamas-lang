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
merge_fixture="$root/regression_tests/recursive_literal_string_merge_result_repro.cr"
printf 'AZ\n' > "$work/bool.expected"
printf 'A\nZ\n' > "$work/string.expected"
printf 'A\nZ\nY\n' > "$work/merge.expected"
# Keep the recursive call and a valid reached return. The final body still
# has to reject the wrong kind or type in a later branch.
awk '{print} $0 == "    evaluate_text(depth &- 1) == 65" {print "    Bool"}' "$bool_fixture" > "$work/wrong_kind.cr"
sed 's/flag(depth) ? "A" : "C"/flag(depth) ? "A" : 17/' "$string_fixture" > "$work/wrong_type.cr"
sed 's/? "Y" : "Z"/? String : "Z"/' "$merge_fixture" > "$work/wrong_merge_kind.cr"
sed 's/? "Y" : "Z"/? 17 : "Z"/' "$merge_fixture" > "$work/wrong_merge_type.cr"
sed 's/flag(depth) ? "A" : "C"/flag(depth) ? "A" : String/' "$merge_fixture" > "$work/wrong_final_merge_kind.cr"

for mode in original lazy eager; do
  case "$mode" in
    original) build=("$safe" "$stock" 60 2048 build --prelude=empty "${link[@]}") ;;
    lazy) build=("$safe" "$candidate" 60 2048 --no-prelude --no-ast-cache --no-llvm-cache) ;;
    eager) build=(env ADAMAS_EAGER_MONO=1 "$safe" "$candidate" 60 2048 --no-prelude --no-ast-cache --no-llvm-cache) ;;
  esac
  for kind in bool string merge; do
    case "$kind" in
      bool) fixture="$bool_fixture" ;;
      string) fixture="$string_fixture" ;;
      merge) fixture="$merge_fixture" ;;
    esac
    "${build[@]}" "$fixture" -o "$work/positive" > "$work/build.log" 2>&1 || { cat "$work/build.log" >&2; exit 1; }
    "$safe" "$work/positive" 5 512 > "$work/positive.out" 2> "$work/run.log" || { cat "$work/run.log" >&2; exit 1; }
    cmp "$work/$kind.expected" "$work/positive.out"
  done
  for invalid in wrong_kind wrong_type wrong_merge_kind wrong_merge_type wrong_final_merge_kind; do
    if "${build[@]}" "$work/$invalid.cr" -o "$work/invalid" > "$work/invalid.log" 2>&1; then
      echo "$mode accepted $invalid" >&2
      exit 1
    fi
    case "$invalid" in
      wrong_kind) diagnostic='Bool.*Bool\.class|Bool\.class.*Bool' ;;
      wrong_merge_kind|wrong_final_merge_kind) diagnostic='String.*String\.class|String\.class.*String' ;;
      wrong_type|wrong_merge_type) diagnostic='String.*Int32|Int32.*String' ;;
    esac
    grep -E "$diagnostic" "$work/invalid.log" >/dev/null || { cat "$work/invalid.log" >&2; exit 1; }
  done
  echo "$mode matched the recursive literal results and rejected invalid result types and kinds"
done
