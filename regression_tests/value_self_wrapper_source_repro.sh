#!/usr/bin/env bash
# Native stock/lazy/eager controls for the concrete value self-wrapper route.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
VALUE_SELF_REPO_ROOT="${VALUE_SELF_REPO_ROOT:-$ROOT_DIR}"
SAFE_RUNNER="${SAFE_RUNNER:-$VALUE_SELF_REPO_ROOT/scripts/run_safe.sh}"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$VALUE_SELF_REPO_ROOT/bin/adamas}}"
CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${CRYSTAL_BIN:-$(command -v crystal || true)}}"
FIXTURES="$ROOT_DIR/spec/fixtures/value_self_wrapper"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/value-self-wrapper.XXXXXX")"
trap 'rm -rf -- "$WORK_DIR"' EXIT
[[ -x "$SAFE_RUNNER" && -x "$ADAMAS_BIN" && -x "$CRYSTAL_BIN" ]] || {
  echo 'missing safe runner or compiler' >&2
  exit 2
}
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
export CRYSTAL_CACHE_DIR="$WORK_DIR/cache"
mkdir -p "$CRYSTAL_CACHE_DIR"

printf 'A\n' >"$WORK_DIR/expected"
for mode in stock lazy eager; do
  binary="$WORK_DIR/$mode.bin"
  if [[ "$mode" == stock ]]; then
    flags=()
    if [[ -n "${ORIGINAL_LINK_FLAGS:-}" ]]; then flags+=("--link-flags=$ORIGINAL_LINK_FLAGS"); fi
    command=("$SAFE_RUNNER" "$CRYSTAL_BIN" 60 4096 build --prelude=empty
      --no-debug --error-trace "${flags[@]}" "$FIXTURES/accepted.cr" -o "$binary")
  else
    command=("$SAFE_RUNNER" "$ADAMAS_BIN" 60 8192 "$FIXTURES/accepted.cr"
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
  printf 'PASS: %s concrete UInt64 self-wrapper control\n' "$mode"
done

for mode in stock lazy eager; do
  binary="$WORK_DIR/negative-$mode.bin"
  if [[ "$mode" == stock ]]; then
    flags=()
    if [[ -n "${ORIGINAL_LINK_FLAGS:-}" ]]; then flags+=("--link-flags=$ORIGINAL_LINK_FLAGS"); fi
    command=("$SAFE_RUNNER" "$CRYSTAL_BIN" 60 4096 build --prelude=empty
      --no-debug --error-trace "${flags[@]}" "$FIXTURES/invalid_two_arguments.cr" -o "$binary")
  else
    command=("$SAFE_RUNNER" "$ADAMAS_BIN" 60 8192 "$FIXTURES/invalid_two_arguments.cr"
      --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$binary")
    if [[ "$mode" == eager ]]; then
      command=(env ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1 "${command[@]}")
    fi
  fi
  set +e
  "${command[@]}" >"$WORK_DIR/negative.log" 2>&1
  status=$?
  set -e
  if [[ "$status" != 1 || -e "$binary" ]] ||
     ! grep -Eiq '(no overload matches|wrong number of arguments).*value_self_contract|value_self_contract.*(no overload matches|wrong number of arguments)' \
       "$WORK_DIR/negative.log"; then
    cat "$WORK_DIR/negative.log" >&2
    echo "FAIL: $mode must reject the incompatible two-argument call semantically" >&2
    exit 1
  fi
  printf 'PASS: %s incompatible UInt64 call rejected\n' "$mode"
done
