#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
fixtures="$root/regression_tests/fixtures/constant_source_value_kind"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-constant-source-kind.XXXXXX")"
cleanup() {
  local result=$?
  if [[ "$result" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'Retained artifacts %s\n' "$work" >&2
  else
    rm -rf -- "$work"
  fi
}
trap cleanup EXIT
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
link_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  link_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

compile() {
  local mode="$1" name="$2" output="$work/$1-$2"
  if [[ "$mode" == original ]]; then
    "$safe" "$original" 90 8192 build "$fixtures/$name.cr" \
      --prelude=empty --no-debug "${link_flags[@]}" -o "$output" \
      >"$output.build.log" 2>&1
  else
    "$safe" "$candidate" 90 8192 "$fixtures/$name.cr" \
      --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$output" \
      >"$output.build.log" 2>&1
  fi
}

for name in direct local qualified type_constant nested_type_shadows_outer_value nested_head_shadows_global generic_value_shadow nested_lib_constant generic_qualified_head generic_tuple_parameter_type generic_rooted_parameter_type ancestor_depth_first; do
  case "$name" in
    direct|local|qualified|generic_value_shadow|nested_lib_constant|generic_qualified_head|generic_tuple_parameter_type|generic_rooted_parameter_type|ancestor_depth_first) printf 'A\n' >"$work/expected" ;;
    *) printf A >"$work/expected" ;;
  esac
  for mode in original candidate; do
    if ! compile "$mode" "$name"; then
      cat "$work/$mode-$name.build.log" >&2
      exit 1
    fi
    "$safe" "$work/$mode-$name" 5 512 \
      >"$work/$mode-$name.stdout" 2>"$work/$mode-$name.run.log"
    diff -u "$work/expected" "$work/$mode-$name.stdout"
  done
  printf 'PASS %s\n' "$name"
done

for name in reject_metaclass reject_local_metaclass reject_qualified_metaclass reject_type_constant_instance reject_mixed_constant_instance reject_ancestor_depth_first reject_unrelated_type; do
  for mode in original candidate; do
    if compile "$mode" "$name"; then
      printf 'Unexpected acceptance by %s of %s\n' "$mode" "$name" >&2
      exit 1
    fi
    diagnostic='no overload|expected.*(Item|class)|must be.*(Item|class)'
    if [[ "$name" == reject_unrelated_type ]]; then
      diagnostic='undefined constant Item'
    fi
    if ! rg -qi "$diagnostic" "$work/$mode-$name.build.log"; then
      cat "$work/$mode-$name.build.log" >&2
      exit 1
    fi
  done
  printf 'PASS %s\n' "$name"
done
