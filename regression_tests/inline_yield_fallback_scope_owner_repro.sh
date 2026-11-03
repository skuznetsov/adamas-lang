#!/usr/bin/env bash
# Preserve exact fallback scope/cache state on failure and capture writeback.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${CRYSTAL_BIN:-/opt/homebrew/opt/crystal/bin/crystal}}"
LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
FIXTURES="$ROOT_DIR/regression_tests/inline_yield_fallback_scope_owner"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/inline-yield-fallback-scope.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  else
    rm -rf -- "$WORK"
  fi
}
trap cleanup EXIT

cases=(direct_capture)
expected=('A')

run_case() {
  local mode="$1" index="$2" route="$3" name="${cases[$2]}" depth=0
  [[ "$route" == disabled_inline ]] && depth=64
  local source="$FIXTURES/$name.cr" binary="$WORK/$mode.$route.$name"
  if [[ "$mode" == stock ]]; then
    env -u ADAMAS_DISABLE_INLINE_YIELD INLINE_YIELD_MAX_DEPTH="$depth" \
      CRYSTAL_CACHE_DIR="$WORK/cache.stock" "$SAFE" "$ORIGINAL_CRYSTAL_BIN" 120 4096 build \
      --prelude=empty --single-module --no-debug --link-flags="$LINK_FLAGS" \
      "$source" -o "$binary" >"$binary.compile.log" 2>&1 || {
        cat "$binary.compile.log" >&2
        return 1
      }
  else
    mode_env=(env -u ADAMAS_DISABLE_INLINE_YIELD -u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO INLINE_YIELD_MAX_DEPTH="$depth")
    [[ "$route" == disabled_inline ]] && mode_env+=(ADAMAS_DISABLE_INLINE_YIELD=1)
    [[ "$mode" == eager ]] && mode_env+=(ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1)
    "${mode_env[@]}" ADAMAS_LLVM_CACHE=0 "$SAFE" "$ADAMAS_BIN" 120 4096 \
      "$source" --no-prelude --no-debug --no-ast-cache --no-llvm-cache \
      -o "$binary" >"$binary.compile.log" 2>&1 || {
        cat "$binary.compile.log" >&2
        return 1
      }
  fi
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$binary" 5 512 \
    >"$binary.stdout" 2>"$binary.run.log" || {
      cat "$binary.run.log" >&2
      return 1
    }
  printf '%s\n' "${expected[$index]}" >"$WORK/$name.expected.stdout"
  diff -u "$WORK/$name.expected.stdout" "$binary.stdout" || return 1
  printf 'PASS: %s %s %s (depth=%s)\n' "$mode" "$route" "$name" "$depth"
}

unit_args=(spec "$ROOT_DIR/spec/hir/inline_yield_fallback_scope_owner_spec.cr"
  "$ROOT_DIR/spec/hir/inline_caller_locals_stack_spec.cr"
  --single-module --error-trace --no-color --link-flags="$LINK_FLAGS")
"$SAFE" "$ORIGINAL_CRYSTAL_BIN" 300 14336 "${unit_args[@]}"

modes=(stock lazy eager)
[[ "${ORIGINAL_ONLY:-0}" == 1 ]] && modes=(stock)
[[ "${CANDIDATE_ONLY:-0}" == 1 ]] && modes=(lazy eager)
for mode in "${modes[@]}"; do
  routes=(depth0 disabled_inline)
  [[ "$mode" == stock ]] && routes=(depth0)
  for route in "${routes[@]}"; do
    for index in "${!cases[@]}"; do
      run_case "$mode" "$index" "$route"
    done
  done
done
