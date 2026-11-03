#!/usr/bin/env bash
# Qualify the actual captured-yield producer and its emitted callback carriers.
# Both native fixtures must print exactly "A\n" with stock Crystal and Adamas.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${CRYSTAL_BIN:-/opt/homebrew/opt/crystal/bin/crystal}}"
ADAMAS_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
STOCK_LINK_FLAGS="${STOCK_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
FIXTURES="$ROOT_DIR/regression_tests/captured_yield_producer"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/captured-yield-producer.XXXXXX")"

cleanup() {
  local status=$?
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  else
    rm -rf -- "$WORK"
  fi
}
trap cleanup EXIT

cases=(direct_capture nested_capture)
variants=(stock lazy eager lazy-disabled eager-disabled)
printf 'A\n' >"$WORK/expected.stdout"

run_focused_specs() {
  local log="$WORK/focused-hir-mir-specs.log"
  local summary
  local -a specs=(
    "$ROOT_DIR/spec/hir/captured_yield_producer_observation_spec.cr"
    "$ROOT_DIR/spec/hir/captured_yield_storage_contract_spec.cr"
    "$ROOT_DIR/spec/mir/captured_yield_target_contract_spec.cr"
    "$ROOT_DIR/spec/mir/heap_yield_callback_carrier_spec.cr"
  )

  if ! CRYSTAL_CACHE_DIR="$WORK/cache.spec" \
    "$SAFE" "$ORIGINAL_CRYSTAL_BIN" 300 8192 spec --no-color "${specs[@]}" >"$log" 2>&1; then
    cat "$log" >&2
    return 1
  fi
  summary="$(awk '/[0-9]+ examples?, [0-9]+ failures?/ { result = $0 } END { print result }' "$log")"
  if [[ -z "$summary" ]]; then
    cat "$log" >&2
    printf 'error: focused HIR/MIR spec run did not report an example summary\n' >&2
    return 1
  fi
  printf 'PASS: focused HIR/MIR specs: %s\n' "$summary"
}

run_stock_case() {
  local name="$1"
  local source="$FIXTURES/$name.cr"
  local binary="$WORK/stock.$name"
  local log="$binary.compile.log"

  if ! CRYSTAL_CACHE_DIR="$WORK/cache.stock" \
    "$SAFE" "$ORIGINAL_CRYSTAL_BIN" 120 4096 build \
      --prelude=empty --single-module --no-debug \
      --link-flags="$STOCK_LINK_FLAGS" "$source" -o "$binary" >"$log" 2>&1; then
    cat "$log" >&2
    return 1
  fi
  compare_output "stock" "$name" "$binary"
}

run_adamas_case() {
  local variant="$1" name="$2"
  local source="$FIXTURES/$name.cr"
  local binary="$WORK/$variant.$name"
  local log="$binary.compile.log"
  local -a mode_env=(
    env -u ADAMAS_DISABLE_INLINE_YIELD -u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO
    INLINE_YIELD_MAX_DEPTH=0 ADAMAS_LLVM_CACHE=0
    ADAMAS_EXTRA_LINK_FLAGS="$ADAMAS_LINK_FLAGS"
  )

  case "$variant" in
    lazy) ;;
    eager) mode_env+=(ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1) ;;
    lazy-disabled) mode_env+=(ADAMAS_DISABLE_INLINE_YIELD=1) ;;
    eager-disabled) mode_env+=(ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1 ADAMAS_DISABLE_INLINE_YIELD=1) ;;
    *) printf 'error: unknown Adamas variant: %s\n' "$variant" >&2; return 2 ;;
  esac

  if ! "${mode_env[@]}" "$SAFE" "$ADAMAS_BIN" 120 4096 \
    "$source" --no-prelude --no-debug --no-ast-cache --no-llvm-cache \
    -o "$binary" >"$log" 2>&1; then
    cat "$log" >&2
    return 1
  fi
  compare_output "$variant" "$name" "$binary"
}

compare_output() {
  local mode="$1" name="$2" binary="$3"
  local stdout="$binary.stdout" log="$binary.run.log"

  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$binary" 5 512 >"$stdout" 2>"$log"; then
    cat "$log" >&2
    return 1
  fi
  if ! cmp -s "$WORK/expected.stdout" "$stdout"; then
    diff -u "$WORK/expected.stdout" "$stdout" >&2 || true
    printf 'FAIL: %s %s output differs byte-for-byte from A\\n\n' "$mode" "$name" >&2
    return 1
  fi
  printf 'PASS: %s %s (INLINE_YIELD_MAX_DEPTH=0)\n' "$mode" "$name"
}

run_focused_specs
for name in "${cases[@]}"; do
  run_stock_case "$name"
done
for variant in "${variants[@]}"; do
  [[ "$variant" == stock ]] && continue
  for name in "${cases[@]}"; do
    run_adamas_case "$variant" "$name"
  done
done
