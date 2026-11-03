#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${CRYSTAL_BIN:-$(command -v crystal || true)}}"
FIXTURES="$ROOT_DIR/spec/fixtures/record_only_macro_order"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macro-record-only-order.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT
[[ -x "$SAFE_RUNNER" && -x "$ADAMAS_BIN" && -x "$CRYSTAL_BIN" ]] || {
  echo 'missing safe runner or compiler' >&2
  exit 2
}
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
compile_fixture() {
  local mode="$1" fixture="$2" binary="$3"
  if [[ "$mode" == stock ]]; then
    local -a flags=()
    if [[ -n "${ORIGINAL_LINK_FLAGS:-}" ]]; then flags+=("--link-flags=$ORIGINAL_LINK_FLAGS"); fi
    "$SAFE_RUNNER" "$CRYSTAL_BIN" 60 4096 build --prelude=empty --no-debug \
      --error-trace "${flags[@]}" "$fixture" -o "$binary"
  elif [[ "$mode" == eager ]]; then
    ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1 "$SAFE_RUNNER" "$ADAMAS_BIN" 60 8192 \
      "$fixture" --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$binary"
  else
    "$SAFE_RUNNER" "$ADAMAS_BIN" 60 8192 \
      "$fixture" --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$binary"
  fi
}
for mode in stock lazy eager; do
  for name in inheritance_parent_before_child namespace_parent_declared enum_body_method_native_control namespace_parent_missing; do
    binary="$WORK_DIR/$name.$mode.bin"
    log="$binary.compile.log"
    if ! compile_fixture "$mode" "$FIXTURES/$name.cr" "$binary" >"$log" 2>&1; then
      cat "$log" >&2
      exit 1
    fi
    RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$binary" 5 512 \
      >"$binary.stdout" 2>"$binary.run.log" || { cat "$binary.run.log" >&2; exit 1; }
    if [[ "$name" == namespace_parent_missing ]]; then
      : >"$WORK_DIR/expected.stdout"
    else
      printf 'A\n' >"$WORK_DIR/expected.stdout"
    fi
    diff -u "$WORK_DIR/expected.stdout" "$binary.stdout"
  done
  log="$WORK_DIR/forward-parent.$mode.compile.log"
  if compile_fixture "$mode" "$FIXTURES/inheritance_child_before_parent.cr" \
       "$WORK_DIR/forward-parent.$mode.bin" >"$log" 2>&1; then
    echo "unexpected forward-superclass acceptance: $mode" >&2
    exit 1
  fi
  if ! grep -q 'undefined constant.*LaterParent' "$log"; then
    cat "$log" >&2
    exit 1
  fi
  printf 'PASS: %s macro declaration order and body publication controls\n' "$mode"
done
