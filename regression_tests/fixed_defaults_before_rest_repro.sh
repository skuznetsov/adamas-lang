#!/usr/bin/env bash
# Verify source binding owns defaults, positional rest values and keyword slots.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
FIXTURE_DIR="$ROOT_DIR/regression_tests/fixtures/fixed_defaults_before_rest"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal || true)}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fixed-defaults-before-rest.XXXXXX")"

cleanup() {
  local rc=$?
  if [[ "$rc" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

POSITIVE_CASES=(
  explicit_index_method
  named_class_method
  missing_default_and_rest_contents
  default_side_effect_once_and_previous_argument
  keyword_only_default_after_rest
  constructor_source_slots
  contextual_enum_symbol
  fixed_overload_precedence
  fixed_same_type_precedence
  fixed_widened_type_precedence
  noreturn_receiver_skips_arguments
  noreturn_rest_actual_skips_keyword
  noreturn_rest_actual_skips_observable_default
  terminal_before_invalid_default
  terminal_before_required_keyword
  terminal_keyword_skips_incompatible_call
  double_splat_formal_preserves_explicit_order
  double_splat_formal_terminal_skips_default
  legacy_symbol_literal_noreturn_keeps_default
  legacy_symbol_terminal_skips_default
  literal_noreturn_keeps_default
  literal_noreturn_named_keeps_default
)
NEGATIVE_CASES=(
  required_keyword_after_rest_rejected
  required_fixed_before_rest_rejected
  required_keyword_after_nonempty_rest_rejected
  terminal_before_invalid_keyword
  flowing_keyword_still_rejects_incompatible_call
  legacy_symbol_visits_invalid_explicit_keyword
  literal_noreturn_still_rejects_incompatible_call
)

[[ -x "$SAFE_RUNNER" ]] || { printf 'missing safe runner: %s\n' "$SAFE_RUNNER" >&2; exit 2; }
[[ -x "$ORIGINAL_CRYSTAL_BIN" ]] || { printf 'set ORIGINAL_CRYSTAL_BIN to the stock Crystal compiler\n' >&2; exit 2; }
[[ -x "$ADAMAS_BIN" ]] || { printf 'set ADAMAS_BIN to the candidate compiler\n' >&2; exit 2; }

compile_positive() {
  local stage="$1" name="$2" source binary log
  source="$FIXTURE_DIR/$name.cr"
  binary="$WORK_DIR/$stage-$name"
  log="$WORK_DIR/$stage-$name.build.log"
  local link_flags=()
  if [[ -n "${ADAMAS_ORIGINAL_LINK_FLAGS:-}" ]]; then
    link_flags=("--link-flags=$ADAMAS_ORIGINAL_LINK_FLAGS")
  fi
  case "$stage" in
    stock)
      if ! "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 240 8192 build --prelude=empty --no-debug \
        "${link_flags[@]}" "$source" -o "$binary" >"$log" 2>&1; then
        cat "$log" >&2
        return 1
      fi
      ;;
    lazy)
      if ! "$SAFE_RUNNER" "$ADAMAS_BIN" 300 8192 "$source" --no-prelude --no-debug \
        --no-ast-cache --no-llvm-cache -o "$binary" >"$log" 2>&1; then
        cat "$log" >&2
        return 1
      fi
      ;;
    eager)
      if ! ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1 "$SAFE_RUNNER" "$ADAMAS_BIN" 300 8192 "$source" \
        --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$binary" >"$log" 2>&1; then
        cat "$log" >&2
        return 1
      fi
      ;;
  esac

  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$binary" 5 512 \
    >"$WORK_DIR/$stage-$name.stdout" 2>"$WORK_DIR/$stage-$name.run.log"; then
    cat "$WORK_DIR/$stage-$name.run.log" >&2
    return 1
  fi
  if ! rg -Fq '[EXIT: 0]' "$WORK_DIR/$stage-$name.run.log"; then
    cat "$WORK_DIR/$stage-$name.run.log" >&2
    return 1
  fi
  diff -u "$FIXTURE_DIR/$name.expected" "$WORK_DIR/$stage-$name.stdout"
  printf 'PASS %s %s\n' "$stage" "$name"
}

compile_negative() {
  local stage="$1" name="$2" source binary log
  source="$FIXTURE_DIR/$name.cr"
  binary="$WORK_DIR/$stage-$name"
  log="$WORK_DIR/$stage-$name.build.log" rc=0
  local link_flags=()
  if [[ -n "${ADAMAS_ORIGINAL_LINK_FLAGS:-}" ]]; then
    link_flags=("--link-flags=$ADAMAS_ORIGINAL_LINK_FLAGS")
  fi
  case "$stage" in
    stock)
      "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 240 8192 build --prelude=empty --no-debug \
        "${link_flags[@]}" "$source" -o "$binary" >"$log" 2>&1 || rc=$?
      ;;
    lazy)
      "$SAFE_RUNNER" "$ADAMAS_BIN" 300 8192 "$source" --no-prelude --no-debug \
        --no-ast-cache --no-llvm-cache -o "$binary" >"$log" 2>&1 || rc=$?
      ;;
    eager)
      ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1 "$SAFE_RUNNER" "$ADAMAS_BIN" 300 8192 "$source" \
        --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$binary" >"$log" 2>&1 || rc=$?
      ;;
  esac
  if [[ "$rc" != 1 ]] || ! rg -qi \
    'missing|must be provided|no overload|no matching|missing argument|argument.*required|wrong number|undefined method' "$log"; then
    cat "$log" >&2
    printf 'FAIL %s %s: expected source argument rejection (exit 1)\n' "$stage" "$name" >&2
    return 1
  fi
  printf 'PASS %s %s (rejected)\n' "$stage" "$name"
}

for name in "${POSITIVE_CASES[@]}"; do
  for stage in stock lazy eager; do
    compile_positive "$stage" "$name"
  done
done

for name in "${NEGATIVE_CASES[@]}"; do
  for stage in stock lazy eager; do
    compile_negative "$stage" "$name"
  done
done

printf 'PASS: source defaults/rest/keyword binding (%d positives, %d rejections; stock/lazy/eager)\n' \
  "${#POSITIVE_CASES[@]}" "${#NEGATIVE_CASES[@]}"
