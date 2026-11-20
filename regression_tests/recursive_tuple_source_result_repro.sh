#!/usr/bin/env bash
# A reached tuple return through a local read can close a recursive type cycle.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
safe="$root/scripts/run_safe.sh"
stock="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
work="$(mktemp -d "${TMPDIR:-/tmp}/recursive-tuple.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

fixture="$root/regression_tests/recursive_tuple_source_result_repro.cr"
printf 'T\n' > "$work/expected"
sed 's/{number != 0, context.with_depth(context.depth \&+ 1)}/{context.with_depth(context.depth \&+ 1), number != 0}/' "$fixture" > "$work/wrong_order.cr"
awk '
  /number != 0, context[.]with_depth/ {sub(/context[.]with_depth/, "WrongContext.new")}
  {print}
  $0 == "  class TupleCycleProbe" {
    print "    class WrongContext"
    print "      def initialize(@depth : Int32)"
    print "      end"
    print "    end"
  }
' "$fixture" > "$work/wrong_slot.cr"

for mode in original lazy eager; do
  case "$mode" in
    original) build=("$safe" "$stock" 60 2048 build --prelude=empty "${link[@]}") ;;
    lazy) build=(env DEBUG_FORCE_LOWER_DEPTH=1 "$safe" "$candidate" 60 2048 --no-prelude --no-ast-cache --no-llvm-cache) ;;
    eager) build=(env ADAMAS_EAGER_MONO=1 "$safe" "$candidate" 60 2048 --no-prelude --no-ast-cache --no-llvm-cache) ;;
  esac
  "${build[@]}" "$fixture" -o "$work/positive" > "$work/build.log" 2>&1 || { cat "$work/build.log" >&2; exit 1; }
  if [[ "$mode" == lazy ]]; then
    grep -E '\[FORCE_LOWER_RECURSIVE_TUPLE\].*evaluate_to_macro_value.*evaluate_condition' "$work/build.log" >/dev/null || { cat "$work/build.log" >&2; exit 1; }
  fi
  "$safe" "$work/positive" 5 512 > "$work/actual" 2> "$work/run.log" || { cat "$work/run.log" >&2; exit 1; }
  cmp "$work/expected" "$work/actual"

  for invalid in wrong_order wrong_slot; do
    if "${build[@]}" "$work/$invalid.cr" -o "$work/invalid" > "$work/invalid.log" 2>&1; then
      echo "$mode accepted $invalid" >&2
      exit 1
    fi
    case "$invalid" in
      wrong_order) diagnostic='must return Tuple\(Bool, .*Context\).*returning Tuple\(.*Context, .*Bool' ;;
      wrong_slot) diagnostic='must return Tuple\(Bool, .*Context\).*returning Tuple\(Bool, .*WrongContext' ;;
    esac
    grep -E "$diagnostic" "$work/invalid.log" >/dev/null || { cat "$work/invalid.log" >&2; exit 1; }
  done
  echo "$mode matched the recursive tuple result and rejected both invalid contracts"
done
