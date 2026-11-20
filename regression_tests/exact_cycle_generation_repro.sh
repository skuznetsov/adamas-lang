#!/usr/bin/env bash
# A depth refusal must preserve the checked results of mutual recursion in either branch order.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
safe="$root/scripts/run_safe.sh"
stock="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
work="$(mktemp -d "${TMPDIR:-/tmp}/exact-cycle-generation.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

fixture="$root/regression_tests/exact_cycle_generation_repro.cr"
sed -e 's/^    if value > 2$/    if value > 8\n      extra(value)\n    elsif value > 2/' \
    -e 's/collector.result(3)/collector.result(9)/' "$fixture" > "$work/multiple_branches.cr"
sed 's/^    pop_table$/    table.missing_table_method\n    pop_table/' "$fixture" > "$work/missing_method.cr"
sed 's/^  private def pop_table$/  private def pop_table : Int32/' "$fixture" > "$work/wrong_return.cr"
sed 's/^  private def extra(value : Int32) : Table$/  private def extra(value : Int32) : Int32/' \
    "$work/multiple_branches.cr" > "$work/wrong_branch_return.cr"
printf '550\n' > "$work/expected"

for mode in original lazy eager; do
  case "$mode" in
    original) build=("$safe" "$stock" 60 2048 build --prelude=empty "${link[@]}") ;;
    lazy) build=("$safe" "$candidate" 60 2048 --no-prelude --no-ast-cache --no-llvm-cache) ;;
    eager) build=(env ADAMAS_EAGER_MONO=1 "$safe" "$candidate" 60 2048 --no-prelude --no-ast-cache --no-llvm-cache) ;;
  esac
  for positive in "$fixture" "$work/multiple_branches.cr"; do
    "${build[@]}" "$positive" -o "$work/positive" > "$work/build.log" 2>&1 || { cat "$work/build.log" >&2; exit 1; }
    "$safe" "$work/positive" 5 512 > "$work/actual" 2> "$work/run.log" || { cat "$work/run.log" >&2; exit 1; }
    cmp "$work/expected" "$work/actual"
  done

  for invalid in missing_method wrong_return wrong_branch_return; do
    if "${build[@]}" "$work/$invalid.cr" -o "$work/invalid" > "$work/invalid.log" 2>&1; then
      echo "$mode accepted $invalid" >&2
      exit 1
    fi
    case "$invalid" in
      missing_method) diagnostic='undefined method.*missing_table_method' ;;
      wrong*return) diagnostic='must return Int32.*returning.*Table' ;;
    esac
    grep -Ei "$diagnostic" "$work/invalid.log" >/dev/null || { cat "$work/invalid.log" >&2; exit 1; }
  done
  echo "$mode matched both recursive branch orders and rejected all invalid bodies"
done
