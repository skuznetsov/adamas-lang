#!/usr/bin/env bash
# Original-first regression for direct source module membership admission.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
COMPILER="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}"
SAFE_RUNNER="${ADAMAS_SAFE_RUNNER:-$ROOT_DIR/scripts/run_safe.sh}"
FIXTURES="$ROOT_DIR/regression_tests/fixtures/module_source_value_kind"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/module-source-value-kind.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf -- "$WORK_DIR"/cache-*
  if [[ "$status" == 0 && "${KEEP_TMP:-0}" != 1 ]]; then
    rm -rf -- "$WORK_DIR"
  else
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  fi
}
trap cleanup EXIT
[[ -x "$COMPILER" && -x "$ORIGINAL" && -x "$SAFE_RUNNER" ]]
export ADAMAS_LLVM_CACHE=0

original_link_flags="${ORIGINAL_CRYSTAL_LINK_FLAGS:-}"
if [[ "$(uname -s)" == Darwin ]]; then
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
  original_link_flags="${original_link_flags:--fuse-ld=/usr/bin/ld}"
fi

# Keep this order: every stock result is recorded before candidate execution.
cases=(
  generic_extend_positive generic_extend_instance_negative
  generic_include_instance_positive generic_include_class_negative
  generic_mismatch_negative same_short_name_namespace_negative
  generic_alias_positive namespace_alias_negative module_reopen_positive
  macro_selected_extend_positive macro_selected_extend_instance_negative
  extend_self_identity extend_self_include_projection nested_byte_format_extend
  named_alias_class named_extended_class named_extended_instance
  named_included_class named_included_instance positional_alias_class
  positional_extended_class positional_extended_instance
  positional_included_class positional_included_instance
  forall_projection_conflict nested_generic_invariance
  nested_class_namespace qualified_class_namespace nested_module_namespace
  nested_class_generic_module
)

for phase in original candidate; do
  for test_case in "${cases[@]}"; do
    cache="$WORK_DIR/cache-$phase-$test_case"
    mkdir "$cache"
    output="$WORK_DIR/$phase-$test_case"
    log="$output.build.log"
    if [[ "$phase" == original ]]; then
      args=(build --prelude=empty --no-debug --error-trace)
      [[ -z "$original_link_flags" ]] || args+=("--link-flags=$original_link_flags")
      args+=("$FIXTURES/$test_case.cr")
      tool="$ORIGINAL"
    else
      args=("$FIXTURES/$test_case.cr" --no-prelude --no-debug --no-ast-cache --no-llvm-cache)
      tool="$COMPILER"
    fi

    status=0
    CRYSTAL_CACHE_DIR="$cache" "$SAFE_RUNNER" "$tool" 180 8192 \
      "${args[@]}" -o "$output" >"$log" 2>&1 || status=$?

    case "$test_case" in
      generic_extend_instance_negative|generic_include_class_negative|generic_mismatch_negative|\
      same_short_name_namespace_negative|namespace_alias_negative|\
      macro_selected_extend_instance_negative|named_extended_instance|\
      named_included_class|positional_extended_instance|positional_included_class|\
      forall_projection_conflict|nested_generic_invariance)
        if [[ "$status" != 1 || -e "$output" ]] || \
          ! grep -Eiq '(^|[[:space:]])error:' "$log" || \
          grep -Eiq 'internal compiler error|segmentation fault|unhandled exception' "$log"; then
          cat "$log" >&2
          exit 1
        fi
        continue
        ;;
    esac

    if [[ "$status" != 0 || ! -x "$output" ]]; then
      cat "$log" >&2
      exit 1
    fi
    if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$output" 5 512 \
        >"$output.stdout" 2>"$output.run.log"; then
      cat "$output.run.log" >&2
      exit 1
    fi

    case "$test_case" in
      generic_include_instance_positive) expected_stdout=$'I\n' ;;
      generic_alias_positive) expected_stdout=$'M\n' ;;
      module_reopen_positive) expected_stdout=$'R\n' ;;
      macro_selected_extend_positive) expected_stdout=$'X\n' ;;
      extend_self_include_projection) expected_stdout=$'F\n' ;;
      nested_byte_format_extend) expected_stdout=$'B\n' ;;
      generic_extend_positive|extend_self_identity|named_alias_class|\
      named_extended_class|named_included_instance|positional_alias_class|\
      positional_extended_class|positional_included_instance|nested_class_namespace|\
      qualified_class_namespace|nested_module_namespace|nested_class_generic_module)
        expected_stdout=$'A\n'
        ;;
      *)
        printf 'no expected output configured for %s\n' "$test_case" >&2
        exit 1
        ;;
    esac
    printf '%s' "$expected_stdout" >"$WORK_DIR/expected.stdout"
    diff -u "$WORK_DIR/expected.stdout" "$output.stdout"
  done
done

echo 'PASS: source module membership preserves module kind, owner, and generic restrictions'
