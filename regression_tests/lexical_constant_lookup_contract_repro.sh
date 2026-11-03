#!/usr/bin/env bash
# Exercise lexical constant ownership through stock Crystal, then Adamas lazy
# and eager lowering. All compiler and generated-binary invocations use the
# repository's resource-limited safe runner.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
FIXTURES="$ROOT_DIR/regression_tests/fixtures/lexical_constant_lookup_contract"
if [[ "$#" -gt 1 ]]; then
  printf 'usage: %s [/path/to/adamas]\n' "$0" >&2
  exit 2
fi
CANDIDATE="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_HINT="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-crystal}}"
if [[ "$ORIGINAL_HINT" == */* ]]; then
  ORIGINAL="$ORIGINAL_HINT"
else
  ORIGINAL="$(command -v "$ORIGINAL_HINT" || true)"
fi
[[ -x "$SAFE_RUNNER" ]] || { printf 'missing safe runner: %s\n' "$SAFE_RUNNER" >&2; exit 2; }
[[ -x "$ORIGINAL" ]] || { printf 'missing original Crystal: %s\n' "$ORIGINAL" >&2; exit 2; }
[[ -x "$CANDIDATE" ]] || { printf 'missing candidate compiler: %s\n' "$CANDIDATE" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/lexical-constant-contract.XXXXXX")"
cleanup() {
  local status=$?
  trap - EXIT
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  else
    rm -rf -- "$WORK"
  fi
}
trap cleanup EXIT

link_args=()
link_env=()
if [[ "$(uname -s)" == Darwin ]]; then
  link_args=(--link-flags=-fuse-ld=/usr/bin/ld)
  link_env=(ADAMAS_EXTRA_LINK_FLAGS=-fuse-ld=/usr/bin/ld)
fi

positive_cases=(
  02_included_method_module_constant_shadows_includer
  04_qualified_nested_module_constant_shadows_includer
  05_inherited_method_parent_constant_shadows_child
  06_lexical_constant_shadows_global
  07_explicit_root_constant
  08_legal_global_fallback_from_included_method
  11_absolute_enum_value
  12_generic_type_constant
  15_included_method_nested_initializer
  16_inherited_method_nested_initializer
  17_lazy_getter_constant_shadow
  18_lazy_getter_receiver_ivar
  20_generic_class_method_declaring_constant
  21_generic_instance_method_declaring_constant
)
negative_cases=(
  01_included_method_missing_includer_constant.reject
  03_qualified_nested_missing_includer_constant.reject
  09_unused_included_method_missing_includer_constant
  10_unused_qualified_nested_missing_includer_constant
  13_qualified_missing_owner.reject
  14_absolute_missing_owner.reject
  19_lazy_getter_missing_declaring_constant.reject
  22_generic_class_method_missing_constant.reject
  23_generic_instance_method_missing_constant.reject
)

compile_original() {
  local name="$1"
  local fixture="$2"
  local binary="$WORK/original.$name"
  mkdir -p "$WORK/cache.original.$name"
  if ! CRYSTAL_CACHE_DIR="$WORK/cache.original.$name" \
      "$SAFE_RUNNER" "$ORIGINAL" 180 8192 build "$fixture" \
      --prelude=empty --no-debug "${link_args[@]}" -o "$binary" \
      >"$WORK/original.$name.build.log" 2>&1; then
    cat "$WORK/original.$name.build.log" >&2
    return 1
  fi
  printf '%s' "$binary"
}

compile_candidate() {
  local mode="$1"
  local name="$2"
  local fixture="$3"
  local binary="$WORK/$mode.$name"
  local -a mode_env=(-u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
  if [[ "$mode" == eager ]]; then
    mode_env+=(ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1)
  fi
  mkdir -p "$WORK/cache.$mode.$name"
  if ! env "${mode_env[@]}" CRYSTAL_CACHE_DIR="$WORK/cache.$mode.$name" \
      ADAMAS_LLVM_CACHE=0 "${link_env[@]}" "$SAFE_RUNNER" "$CANDIDATE" \
      180 8192 "$fixture" --no-prelude --no-debug --no-ast-cache \
      --no-llvm-cache -o "$binary" >"$WORK/$mode.$name.build.log" 2>&1; then
    cat "$WORK/$mode.$name.build.log" >&2
    return 1
  fi
  printf '%s' "$binary"
}

run_positive() {
  local stage="$1"
  local name="$2"
  local binary="$3"
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$binary" 10 512 \
      >"$WORK/$stage.$name.stdout" 2>"$WORK/$stage.$name.run.log"; then
    cat "$WORK/$stage.$name.run.log" >&2
    return 1
  fi
  if ! cmp -s "$FIXTURES/$name.expected" "$WORK/$stage.$name.stdout"; then
    printf 'OUTPUT_MISMATCH[%s:%s]\n' "$stage" "$name" >&2
    diff -u "$FIXTURES/$name.expected" "$WORK/$stage.$name.stdout" >&2 || true
    return 1
  fi
}

expect_rejection() {
  local stage="$1"
  local name="$2"
  local fixture="$3"
  local expected_file="$4"
  local status=0
  local log="$WORK/$stage.$name.reject.log"
  if [[ "$stage" == original ]]; then
    mkdir -p "$WORK/cache.$stage.$name"
    if CRYSTAL_CACHE_DIR="$WORK/cache.$stage.$name" \
        "$SAFE_RUNNER" "$ORIGINAL" 180 8192 build "$fixture" \
        --prelude=empty --no-debug "${link_args[@]}" \
        -o "$WORK/$stage.$name.bin" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  else
    local -a mode_env=(-u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
    if [[ "$stage" == eager ]]; then
      mode_env+=(ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1)
    fi
    mkdir -p "$WORK/cache.$stage.$name"
    if env "${mode_env[@]}" CRYSTAL_CACHE_DIR="$WORK/cache.$stage.$name" \
        ADAMAS_LLVM_CACHE=0 "${link_env[@]}" "$SAFE_RUNNER" "$CANDIDATE" \
        180 8192 "$fixture" --no-prelude --no-debug --no-ast-cache \
        --no-llvm-cache -o "$WORK/$stage.$name.bin" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  fi
  local expected
  expected="$(cat "$expected_file")"
  if [[ "$status" != 1 ]] || ! grep -Fq -- "$expected" "$log"; then
    printf 'EXPECTED_SOURCE_REJECTION[%s:%s] status=%s expected=%s\n' \
      "$stage" "$name" "$status" "$expected" >&2
    cat "$log" >&2
    return 1
  fi
}

# Establish every stock oracle before compiling any candidate fixture.
for name in "${positive_cases[@]}"; do
  fixture="$FIXTURES/$name.cr"
  original="$(compile_original "$name" "$fixture")"
  run_positive original "$name" "$original"
done
for name in "${negative_cases[@]}"; do
  expect_rejection original "$name" "$FIXTURES/$name.cr" \
    "$FIXTURES/$name.stock.reject"
done

for mode in lazy eager; do
  for name in "${positive_cases[@]}"; do
    fixture="$FIXTURES/$name.cr"
    candidate="$(compile_candidate "$mode" "$name" "$fixture")"
    run_positive "$mode" "$name" "$candidate"
  done
  for name in "${negative_cases[@]}"; do
    expect_rejection "$mode" "$name" "$FIXTURES/$name.cr" \
      "$FIXTURES/$name.candidate.reject"
  done
done

printf 'PASS: lexical constant lookup matches stock Crystal in lazy and eager HIR modes\n'
