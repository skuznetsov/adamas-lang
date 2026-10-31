#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
CANDIDATE="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-/opt/homebrew/opt/crystal/share/crystal/src}"
LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pointer-nil-field-contract.XXXXXX")"
FIXTURE="$ROOT_DIR/regression_tests/pointer_nil_union_class_field_contract.cr"

cleanup() {
  local status=$?
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT

if [[ ! -x "$SAFE_RUNNER" || ! -x "$ORIGINAL" || ! -f "$CRYSTAL_STDLIB/empty.cr" || ! -f "$FIXTURE" ]]; then
  echo "ERROR: safe runner, stock Crystal, stock stdlib, or fixture is unavailable" >&2
  exit 2
fi
if [[ "${ORIGINAL_ONLY:-0}" != 1 && ! -x "$CANDIDATE" ]]; then
  echo "ERROR: candidate Adamas compiler is unavailable: $CANDIDATE" >&2
  exit 2
fi

printf 'ACB' >"$WORK_DIR/expected.stdout"

compile_stock() {
  CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/stock-cache" \
    "$SAFE_RUNNER" "$ORIGINAL" 120 4096 build --prelude=empty --no-debug "$FIXTURE" \
    -o "$WORK_DIR/stock.bin" "--link-flags=$LINK_FLAGS" \
    >"$WORK_DIR/stock.build.log" 2>&1
}

compile_candidate() {
  local mode="$1"
  local -a mode_env
  if [[ "$mode" == eager ]]; then
    mode_env=(env -u ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO=1)
  else
    mode_env=(env -u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
  fi
  CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/cache-$mode" \
    ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS="$LINK_FLAGS" "${mode_env[@]}" \
    "$SAFE_RUNNER" "$CANDIDATE" 120 4096 "$FIXTURE" --no-prelude --no-debug \
    --no-ast-cache --no-llvm-cache -o "$WORK_DIR/candidate-$mode.bin" \
    >"$WORK_DIR/candidate-$mode.build.log" 2>&1
}

run_and_compare() {
  local name="$1" binary="$2"
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$binary" 5 512 \
    >"$WORK_DIR/$name.stdout" 2>"$WORK_DIR/$name.run.log"
  diff -u "$WORK_DIR/expected.stdout" "$WORK_DIR/$name.stdout"
}

compile_stock || { cat "$WORK_DIR/stock.build.log" >&2; echo 'FAIL: stock compile' >&2; exit 1; }
run_and_compare stock "$WORK_DIR/stock.bin"
printf 'PASS: stock tagged Pointer | Nil field layout\n'

if [[ "${ORIGINAL_ONLY:-0}" == 1 ]]; then
  exit 0
fi

for mode in lazy eager; do
  compile_candidate "$mode" || { cat "$WORK_DIR/candidate-$mode.build.log" >&2; printf 'FAIL: candidate %s compile\n' "$mode" >&2; exit 1; }
  run_and_compare "$mode" "$WORK_DIR/candidate-$mode.bin"
  printf 'PASS: candidate %s tagged Pointer | Nil field layout\n' "$mode"
done
