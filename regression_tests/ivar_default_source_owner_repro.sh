#!/usr/bin/env bash
# Field initializers retain declaration scope, metaclass self and generic
# bindings independently of the allocator, includer and subclass.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
FIXTURES="$ROOT_DIR/regression_tests/fixtures/ivar_default_source_owner"
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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/ivar-default-source-owner.XXXXXX")"
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

compile_original() {
  local name="$1" fixture="$2"
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
  local mode="$1" name="$2" fixture="$3"
  local binary="$WORK/$mode.$name"
  local mode_env=(-u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
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
  local stage="$1" name="$2" binary="$3"
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

for name in getter_default_evaluation allocator_local_isolation class_body_self constant_once generic_module \
    inline_caller_local_isolation module_self nested_owner overloaded_allocator \
    union_shadow module_constant_shadow inherited_constant_shadow; do
  original="$(compile_original "$name" "$FIXTURES/$name.cr")"
  run_positive original "$name" "$original"
  for mode in lazy eager; do
    candidate="$(compile_candidate "$mode" "$name" "$FIXTURES/$name.cr")"
    run_positive "$mode" "$name" "$candidate"
  done
done

expect_rejection() {
  local stage="$1" name="$2" fixture="$3" status=0
  local log="$WORK/$stage.$name.reject.log"
  if [[ "$stage" == original ]]; then
    mkdir -p "$WORK/cache.$stage.$name"
    CRYSTAL_CACHE_DIR="$WORK/cache.$stage.$name" "$SAFE_RUNNER" "$ORIGINAL" \
      180 8192 build "$fixture" --prelude=empty --no-debug "${link_args[@]}" \
      -o "$WORK/$stage.$name.bin" >"$log" 2>&1 || status=$?
  else
    local mode_env=(-u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
    if [[ "$stage" == eager ]]; then
      mode_env+=(ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1)
    fi
    mkdir -p "$WORK/cache.$stage.$name"
    env "${mode_env[@]}" CRYSTAL_CACHE_DIR="$WORK/cache.$stage.$name" \
      ADAMAS_LLVM_CACHE=0 "${link_env[@]}" "$SAFE_RUNNER" "$CANDIDATE" \
      180 8192 "$fixture" --no-prelude --no-debug --no-ast-cache \
      --no-llvm-cache -o "$WORK/$stage.$name.bin" >"$log" 2>&1 || status=$?
  fi
  if [[ "$status" != 1 ]] || ! grep -Eiq 'undefined constant.*ABSENT_CODE' "$log"; then
    printf 'EXPECTED_SOURCE_REJECTION[%s:%s] status=%s\n' "$stage" "$name" "$status" >&2
    cat "$log" >&2
    return 1
  fi
}

expect_rejection original unknown_owner_constant "$FIXTURES/unknown_owner_constant.cr"
expect_rejection lazy unknown_owner_constant "$FIXTURES/unknown_owner_constant.cr"
expect_rejection eager unknown_owner_constant "$FIXTURES/unknown_owner_constant.cr"
printf 'PASS: ivar initializer declaration scope and rejection match original Crystal\n'
