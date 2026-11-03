#!/usr/bin/env bash
# A source method's yield stays legal when it is inlined into a Proc body,
# while a nested caller block inherits that Proc's lexical yield prohibition.
# The source-matched six-case matrix also checks diagnostic precedence.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${CRYSTAL_BIN:-/opt/homebrew/opt/crystal/bin/crystal}}"
LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
FIXTURES="$ROOT_DIR/regression_tests/yield_lexical_owner"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/yield-lexical-owner.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  else
    rm -rf -- "$WORK"
  fi
}
trap cleanup EXIT

diagnostic="can't use \`yield\` inside a proc literal or captured block"

compile_stock() {
  local source="$1" binary="$2" log="$3"
  CRYSTAL_CACHE_DIR="$WORK/cache.stock" "$SAFE" "$ORIGINAL_CRYSTAL_BIN" 120 4096 build \
    --prelude=empty --single-module --no-debug --link-flags="$LINK_FLAGS" \
    "$source" -o "$binary" >"$log" 2>&1
}

compile_candidate() {
  local mode="$1" source="$2" binary="$3" log="$4"
  local mode_env=(env -u ADAMAS_DISABLE_INLINE_YIELD -u INLINE_YIELD_MAX_DEPTH -u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
  case "$mode" in
    default) ;;
    depth0) mode_env+=(INLINE_YIELD_MAX_DEPTH=0) ;;
    disabled_inline) mode_env+=(ADAMAS_DISABLE_INLINE_YIELD=1) ;;
    *) printf 'unknown candidate mode: %s\n' "$mode" >&2; return 2 ;;
  esac
  ADAMAS_EXTRA_LINK_FLAGS="$LINK_FLAGS" "${mode_env[@]}" ADAMAS_LLVM_CACHE=0 "$SAFE" "$ADAMAS_BIN" 120 8192 \
    "$source" --no-prelude --no-debug --no-ast-cache --no-llvm-cache \
    -o "$binary" >"$log" 2>&1
}

compile_stock_with_prelude() {
  local source="$1" binary="$2" log="$3"
  CRYSTAL_CACHE_DIR="$WORK/cache.stock.prelude" "$SAFE" "$ORIGINAL_CRYSTAL_BIN" 120 4096 build \
    --single-module --no-debug --link-flags="$LINK_FLAGS" \
    "$source" -o "$binary" >"$log" 2>&1
}

compile_candidate_with_prelude() {
  local mode="$1" source="$2" binary="$3" log="$4"
  local mode_env=(env -u ADAMAS_DISABLE_INLINE_YIELD -u INLINE_YIELD_MAX_DEPTH -u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
  case "$mode" in
    default) ;;
    depth0) mode_env+=(INLINE_YIELD_MAX_DEPTH=0) ;;
    disabled_inline) mode_env+=(ADAMAS_DISABLE_INLINE_YIELD=1) ;;
    *) printf 'unknown candidate mode: %s\n' "$mode" >&2; return 2 ;;
  esac
  ADAMAS_EXTRA_LINK_FLAGS="$LINK_FLAGS" "${mode_env[@]}" ADAMAS_LLVM_CACHE=0 "$SAFE" "$ADAMAS_BIN" 120 8192 \
    "$source" --no-debug --no-ast-cache --no-llvm-cache \
    -o "$binary" >"$log" 2>&1
}

expect_rejection() {
  local label="$1" log="$2"
  if ! rg -Fq "$diagnostic" "$log"; then
    printf 'FAIL: %s did not report the Crystal Proc-yield diagnostic\n' "$label" >&2
    cat "$log" >&2
    return 1
  fi
  printf 'PASS: %s rejected Proc-context yield\n' "$label"
}

expect_absent() {
  local label="$1" log="$2" text="$3"
  if rg -Fq "$text" "$log"; then
    printf 'FAIL: %s unexpectedly reported %s\n' "$label" "$text" >&2
    cat "$log" >&2
    return 1
  fi
  printf 'PASS: %s did not visit %s\n' "$label" "$text"
}

# Source excerpts can contain the missing argument's name even when the
# compiler correctly rejects the enclosing yield before visiting it.
expect_no_argument_resolution_error() {
  local label="$1" log="$2"
  if rg -q '^[[:space:]]*[Ee]rror:.*missing_yield_argument' "$log"; then
    printf 'FAIL: %s resolved the forbidden yield argument\n' "$label" >&2
    cat "$log" >&2
    return 1
  fi
  printf 'PASS: %s rejected yield before resolving its argument\n' "$label"
}

run_positive() {
  local label="$1" binary="$2" expected="$WORK/expected.stdout"
  printf 'A\n' >"$expected"
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$binary" 5 512 \
    >"$binary.stdout" 2>"$binary.run.log" || {
      cat "$binary.run.log" >&2
      return 1
    }
  diff -u "$expected" "$binary.stdout"
  printf 'PASS: %s preserved helper yield output\n' "$label"
}

allowed="$FIXTURES/allowed_helper_yield.cr"
forbidden="$FIXTURES/forbidden_nested_proc_yield.cr"
typed_unused="$FIXTURES/typed_unused_block_yield.cr"

stock_allowed="$WORK/stock.allowed"
if ! compile_stock "$allowed" "$stock_allowed" "$WORK/stock.allowed.compile.log"; then
  cat "$WORK/stock.allowed.compile.log" >&2
  exit 1
fi
run_positive stock.allowed "$stock_allowed"

if compile_stock "$forbidden" "$WORK/stock.forbidden" "$WORK/stock.forbidden.compile.log"; then
  printf 'FAIL: stock Crystal accepted yield in a nested Proc-literal block\n' >&2
  exit 1
fi
expect_rejection stock.forbidden "$WORK/stock.forbidden.compile.log"

if ! compile_stock "$typed_unused" "$WORK/stock.typed_unused" "$WORK/stock.typed_unused.compile.log"; then
  cat "$WORK/stock.typed_unused.compile.log" >&2
  exit 1
fi
run_positive stock.typed_unused "$WORK/stock.typed_unused"

for mode in default depth0 disabled_inline; do
  candidate_allowed="$WORK/$mode.allowed"
  if ! compile_candidate "$mode" "$allowed" "$candidate_allowed" "$WORK/$mode.allowed.compile.log"; then
    cat "$WORK/$mode.allowed.compile.log" >&2
    exit 1
  fi
  run_positive "$mode.allowed" "$candidate_allowed"

  if compile_candidate "$mode" "$forbidden" "$WORK/$mode.forbidden" "$WORK/$mode.forbidden.compile.log"; then
    printf 'FAIL: Adamas accepted nested Proc-context yield in mode %s\n' "$mode" >&2
    exit 1
  fi
  expect_rejection "$mode.forbidden" "$WORK/$mode.forbidden.compile.log"

  candidate_typed_unused="$WORK/$mode.typed_unused"
  if ! compile_candidate "$mode" "$typed_unused" "$candidate_typed_unused" "$WORK/$mode.typed_unused.compile.log"; then
    cat "$WORK/$mode.typed_unused.compile.log" >&2
    exit 1
  fi
  run_positive "$mode.typed_unused" "$candidate_typed_unused"
done

# Preserve the six source-matched scope controls. The method-owned positive
# case is compiled and run; all five Proc/capture forms must stop at the
# source-level yield prohibition. Run the full matrix in default mode so the
# three execution-mode controls above stay bounded.
matrix="$FIXTURES/matrix"
matrix_positive=(nested_method_yield)
matrix_rejected=(proc_literal_direct proc_literal_argument_precedence proc_literal_argument_macro macro_expanded_proc_literal_yield source_captured_block_yield)
for case_name in "${matrix_positive[@]}"; do
  source="$matrix/$case_name.cr"
  if ! compile_stock "$source" "$WORK/stock.$case_name" "$WORK/stock.$case_name.compile.log"; then
    cat "$WORK/stock.$case_name.compile.log" >&2
    exit 1
  fi
  run_positive "stock.$case_name" "$WORK/stock.$case_name"
  if ! compile_candidate default "$source" "$WORK/default.$case_name" "$WORK/default.$case_name.compile.log"; then
    cat "$WORK/default.$case_name.compile.log" >&2
    exit 1
  fi
  run_positive "default.$case_name" "$WORK/default.$case_name"
done

for case_name in "${matrix_rejected[@]}"; do
  source="$matrix/$case_name.cr"
  if compile_stock "$source" "$WORK/stock.$case_name" "$WORK/stock.$case_name.compile.log"; then
    printf 'FAIL: stock Crystal accepted %s\n' "$case_name" >&2
    exit 1
  fi
  expect_rejection "stock.$case_name" "$WORK/stock.$case_name.compile.log"
  case "$case_name" in
    proc_literal_argument_precedence)
      expect_no_argument_resolution_error "stock.$case_name" "$WORK/stock.$case_name.compile.log"
      ;;
    proc_literal_argument_macro)
      expect_absent "stock.$case_name" "$WORK/stock.$case_name.compile.log" "yield argument expansion marker"
      ;;
  esac
  if compile_candidate default "$source" "$WORK/default.$case_name" "$WORK/default.$case_name.compile.log"; then
    printf 'FAIL: Adamas accepted %s\n' "$case_name" >&2
    exit 1
  fi
  expect_rejection "default.$case_name" "$WORK/default.$case_name.compile.log"
  case "$case_name" in
    proc_literal_argument_precedence)
      expect_no_argument_resolution_error "default.$case_name" "$WORK/default.$case_name.compile.log"
      ;;
    proc_literal_argument_macro)
      expect_absent "default.$case_name" "$WORK/default.$case_name.compile.log" "yield argument expansion marker"
      ;;
  esac
done

# Force the captured-block path through lower_block_to_proc as well as the
# default inline path. Both must retain the source method's capture ban.
for mode in depth0 disabled_inline; do
  source="$matrix/source_captured_block_yield.cr"
  if compile_candidate "$mode" "$source" "$WORK/$mode.source_captured_block_yield" "$WORK/$mode.source_captured_block_yield.compile.log"; then
    printf 'FAIL: Adamas accepted captured-block yield in mode %s\n' "$mode" >&2
    exit 1
  fi
  expect_rejection "$mode.source_captured_block_yield" "$WORK/$mode.source_captured_block_yield.compile.log"
done

# Proc.new's block is converted to a Proc literal by Crystal's selected
# `&block : self` contract. This source needs the stdlib, so keep it out of the
# no-prelude matrix and make its paired oracle opt-in until the prelude gate is
# available. A mismatch in either direction is a failure.
if [[ "${RUN_PROC_NEW_YIELD_PRELUDE_ORACLE:-0}" == 1 ]]; then
  proc_new="$FIXTURES/proc_new_captured_yield.cr"
  if compile_stock_with_prelude "$proc_new" "$WORK/stock.proc_new" "$WORK/stock.proc_new.compile.log"; then
    proc_new_stock=accepted
  else
    expect_rejection stock.proc_new "$WORK/stock.proc_new.compile.log"
    proc_new_stock=rejected
  fi
  for mode in default depth0 disabled_inline; do
    if [[ "$proc_new_stock" == accepted ]]; then
      if ! compile_candidate_with_prelude "$mode" "$proc_new" "$WORK/$mode.proc_new" "$WORK/$mode.proc_new.compile.log"; then
        cat "$WORK/$mode.proc_new.compile.log" >&2
        exit 1
      fi
    else
      if compile_candidate_with_prelude "$mode" "$proc_new" "$WORK/$mode.proc_new" "$WORK/$mode.proc_new.compile.log"; then
        printf 'FAIL: Adamas accepted Proc.new yield in mode %s while stock rejects it\n' "$mode" >&2
        exit 1
      fi
      expect_rejection "$mode.proc_new" "$WORK/$mode.proc_new.compile.log"
    fi
  done
fi
