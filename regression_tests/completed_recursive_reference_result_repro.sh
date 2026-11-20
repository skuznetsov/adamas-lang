#!/usr/bin/env bash
# A recursive call through an inline block still runs when its result is unused.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
safe="$root/scripts/run_safe.sh"
stock="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
work="$(mktemp -d "${TMPDIR:-/tmp}/completed-recursive-reference.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

fixture="$root/regression_tests/completed_recursive_reference_result_repro.cr"
sed '/^  private def handle_def(value : Int32)$/a\
    return if value == 1
' "$fixture" > "$work/nilable.cr"
sed 's/^  private def pop_table$/  private def pop_table : Int32/' "$fixture" > "$work/wrong_return.cr"
sed '/^      visit(child)$/a\
      table.missing_table_method
' "$fixture" > "$work/missing_method.cr"
printf '54505\n' > "$work/reference.expected"
printf '53500\n' > "$work/nilable.expected"

for mode in original lazy eager; do
  case "$mode" in
    original) build=("$safe" "$stock" 60 2048 build --prelude=empty "${link[@]}") ;;
    lazy) build=("$safe" "$candidate" 60 2048 --no-prelude --no-ast-cache --no-llvm-cache) ;;
    eager) build=(env ADAMAS_EAGER_MONO=1 "$safe" "$candidate" 60 2048 --no-prelude --no-ast-cache --no-llvm-cache) ;;
  esac
  for sample in reference nilable; do
    source="$fixture"
    [[ "$sample" != nilable ]] || source="$work/nilable.cr"
    "${build[@]}" "$source" -o "$work/program" > "$work/build.log" 2>&1 || { cat "$work/build.log" >&2; exit 1; }
    "$safe" "$work/program" 5 512 > "$work/actual" 2> "$work/run.log" || { cat "$work/run.log" >&2; exit 1; }
    cmp "$work/$sample.expected" "$work/actual"
  done

  for invalid in wrong_return missing_method; do
    if "${build[@]}" "$work/$invalid.cr" -o "$work/invalid" > "$work/invalid.log" 2>&1; then
      echo "$mode accepted $invalid" >&2
      exit 1
    fi
    case "$invalid" in
      wrong_return) diagnostic='must return Int32.*returning.*Table' ;;
      missing_method) diagnostic='undefined method.*missing_table_method' ;;
    esac
    grep -Ei "$diagnostic" "$work/invalid.log" >/dev/null || { cat "$work/invalid.log" >&2; exit 1; }
  done
  echo "$mode preserved recursive side effects and both result carriers and rejected invalid bodies"
done
