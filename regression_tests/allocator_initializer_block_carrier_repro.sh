#!/usr/bin/env bash
# A completed initializer owns both its nominal block type and physical carrier.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${CRYSTAL_BIN:-$(command -v crystal || true)}}"
FIXTURES="$ROOT_DIR/spec/fixtures/allocator_initializer_block_carrier"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/initializer-block-carrier.XXXXXX")"
trap 'rm -rf -- "$WORK_DIR"' EXIT
[[ -x "$SAFE_RUNNER" && -x "$ADAMAS_BIN" && -x "$CRYSTAL_BIN" ]] || {
  echo 'missing safe runner or compiler' >&2
  exit 2
}
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
spec_flags=()
if [[ -n "${ORIGINAL_LINK_FLAGS:-}" ]]; then spec_flags+=("--link-flags=$ORIGINAL_LINK_FLAGS"); fi
(cd "$ROOT_DIR" && "$SAFE_RUNNER" "$CRYSTAL_BIN" 180 14336 spec \
  spec/hir/allocator_initializer_block_carrier_spec.cr \
  spec/hir/materialized_initializer_source_spec.cr \
  spec/hir/initializer_layout_replay_spec.cr \
  spec/hir/pending_queue_layout_invalidation_spec.cr \
  "${spec_flags[@]}" --single-module --no-debug) >"$WORK_DIR/spec.log" 2>&1 || {
  cat "$WORK_DIR/spec.log" >&2
  exit 1
}
cat "$WORK_DIR/spec.log"
for name in explicit_raw_block implicit_yield heap_callback; do
  printf 'A\n' >"$WORK_DIR/expected"
  FIXTURE="$FIXTURES/$name.cr"
  for mode in stock lazy eager; do
    binary="$WORK_DIR/$mode.bin"
    if [[ "$mode" == stock ]]; then
      flags=()
      if [[ -n "${ORIGINAL_LINK_FLAGS:-}" ]]; then flags+=("--link-flags=$ORIGINAL_LINK_FLAGS"); fi
      command=("$SAFE_RUNNER" "$CRYSTAL_BIN" 60 4096 build --prelude=empty
        --no-debug --error-trace "${flags[@]}" "$FIXTURE" -o "$binary")
    else
      command=("$SAFE_RUNNER" "$ADAMAS_BIN" 60 8192 "$FIXTURE"
        --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$binary")
      if [[ "$mode" == eager ]]; then
        command=(env ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1 "${command[@]}")
      fi
    fi
    if ! "${command[@]}" >"$WORK_DIR/build.log" 2>&1; then
      cat "$WORK_DIR/build.log" >&2
      exit 1
    fi
    if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$binary" 5 512 \
         >"$WORK_DIR/actual" 2>"$WORK_DIR/run.log"; then
      cat "$WORK_DIR/run.log" >&2
      exit 1
    fi
    diff -u "$WORK_DIR/expected" "$WORK_DIR/actual"
    printf 'PASS: %s %s initializer block carrier native control\n' "$name" "$mode"
  done
done
