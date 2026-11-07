#!/usr/bin/env bash
# Completed Void results must not be confused with unresolved source results.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${CRYSTAL_BIN:-$(command -v crystal || true)}}"
FIXTURES="$ROOT_DIR/spec/fixtures/authenticated_void_result"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/authenticated-void-result.XXXXXX")"
trap 'rm -rf -- "$WORK_DIR"' EXIT
[[ -x "$SAFE_RUNNER" && -x "$ADAMAS_BIN" && -x "$CRYSTAL_BIN" ]] || {
  echo 'missing safe runner or compiler' >&2
  exit 2
}
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
for name in void_chain discard_chain void_branches; do
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
    printf 'PASS: %s %s authenticated Void result native control\n' "$name" "$mode"
  done
done
# A known Void result does not admit incompatible source arguments.
for mode in stock lazy eager; do
  binary="$WORK_DIR/negative-$mode.bin"
  fixture="$FIXTURES/invalid_extern_argument.cr"
  if [[ "$mode" == stock ]]; then
    flags=()
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
  set +e
  "${command[@]}" >"$WORK_DIR/negative.log" 2>&1
  status=$?
  set -e
  if [[ "$status" != 1 || -e "$binary" ]]; then
    cat "$WORK_DIR/negative.log" >&2
    echo "FAIL: $mode must reject an incompatible C argument before emitting a binary" >&2
    exit 1
  fi
  printf 'PASS: %s incompatible Void-call argument rejected\n' "$mode"
done
