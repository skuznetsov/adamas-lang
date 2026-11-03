#!/usr/bin/env bash
# Concrete Proc receivers retain their source signature and strict call contract.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${CRYSTAL_BIN:-$(command -v crystal || true)}}"
FIXTURES="$ROOT_DIR/regression_tests/proc_receiver_materialization"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/proc-receiver-materialization.XXXXXX")"
trap 'rm -rf -- "$WORK_DIR"' EXIT
[[ -x "$SAFE_RUNNER" && -x "$ADAMAS_BIN" && -x "$CRYSTAL_BIN" ]] || {
  echo 'missing safe runner or compiler' >&2
  exit 2
}
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
compile_fixture() {
  local mode="$1" fixture="$2" binary="$3"
  local -a command flags=()
  if [[ "$mode" == stock ]]; then
    if [[ -n "${ORIGINAL_LINK_FLAGS:-}" ]]; then flags+=("--link-flags=$ORIGINAL_LINK_FLAGS"); fi
    command=("$SAFE_RUNNER" "$CRYSTAL_BIN" 60 4096 build --prelude=empty
      --no-debug --error-trace "${flags[@]}" "$fixture" -o "$binary")
  else
    command=("$SAFE_RUNNER" "$ADAMAS_BIN" 60 8192 "$fixture"
      --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$binary")
    if [[ "$mode" == eager ]]; then
      command=(env ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1 "${command[@]}")
    fi
  fi
  "${command[@]}"
}
for name in receiver_methods nested_signatures; do
  for mode in stock lazy eager; do
    binary="$WORK_DIR/$mode.bin"
    if ! compile_fixture "$mode" "$FIXTURES/$name.cr" "$binary" >"$WORK_DIR/build.log" 2>&1; then
      cat "$WORK_DIR/build.log" >&2
      exit 1
    fi
    if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$binary" 5 512 \
         >"$WORK_DIR/actual" 2>"$WORK_DIR/run.log"; then
      cat "$WORK_DIR/run.log" >&2
      exit 1
    fi
    diff -u "$FIXTURES/$name.expected" "$WORK_DIR/actual"
    printf 'PASS: %s %s native Proc receiver control\n' "$name" "$mode"
  done
done
for name in reject_implicit_argument reject_nested_signature reject_class_instance_argument reject_class_receiver; do
  case "$name" in
    reject_implicit_argument) diagnostic="no overload matches 'Proc(Char, Int32)#call'" ;;
    reject_nested_signature) diagnostic="no overload matches 'Proc(Proc(Char, Int32), Int32)#call'" ;;
    reject_class_instance_argument) diagnostic="no overload matches 'Proc(Owner.class, Int32)#call'" ;;
    reject_class_receiver) diagnostic='cannot call Proc#call without a concrete Proc signature' ;;
  esac
  for mode in stock lazy eager; do
    status=0
    compile_fixture "$mode" "$FIXTURES/$name.cr" "$WORK_DIR/$mode.bin" \
      >"$WORK_DIR/build.log" 2>&1 || status=$?
    if [[ "$status" != 1 ]]; then
      cat "$WORK_DIR/build.log" >&2
      echo "expected semantic rejection (exit 1), got $status: $name $mode" >&2
      exit 1
    fi
    if [[ "$mode" != stock ]] && ! grep -Fq "error: $diagnostic" "$WORK_DIR/build.log"; then
      cat "$WORK_DIR/build.log" >&2
      echo "unexpected rejection reason: $name $mode" >&2
      exit 1
    fi
    printf 'PASS: %s %s strict Proc receiver rejection\n' "$name" "$mode"
  done
done
