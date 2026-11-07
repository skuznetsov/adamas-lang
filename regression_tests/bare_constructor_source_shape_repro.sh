#!/usr/bin/env bash
# Bare explicit constructors retain exact named-only default source shape.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
BARE_CONSTRUCTOR_REPO_ROOT="${BARE_CONSTRUCTOR_REPO_ROOT:-$ROOT_DIR}"
SAFE_RUNNER="${SAFE_RUNNER:-$BARE_CONSTRUCTOR_REPO_ROOT/scripts/run_safe.sh}"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$BARE_CONSTRUCTOR_REPO_ROOT/bin/adamas}}"
CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${CRYSTAL_BIN:-$(command -v crystal || true)}}"
FIXTURES="$ROOT_DIR/regression_tests/fixtures/defaulted_call_target"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bare-constructor-shape.XXXXXX")"
trap 'rm -rf -- "$WORK_DIR"' EXIT
[[ -x "$SAFE_RUNNER" && -x "$ADAMAS_BIN" && -x "$CRYSTAL_BIN" ]] || {
  echo 'missing safe runner or compiler' >&2
  exit 2
}
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
export CRYSTAL_CACHE_DIR="$WORK_DIR/cache"
mkdir -p "$CRYSTAL_CACHE_DIR"

printf 'AAB\n' >"$WORK_DIR/expected"
for mode in stock lazy eager; do
  binary="$WORK_DIR/$mode.bin"
  if [[ "$mode" == stock ]]; then
    flags=()
    if [[ -n "${ORIGINAL_LINK_FLAGS:-}" ]]; then flags+=("--link-flags=$ORIGINAL_LINK_FLAGS"); fi
    command=("$SAFE_RUNNER" "$CRYSTAL_BIN" 60 4096 build --prelude=empty
      --no-debug --error-trace "${flags[@]}" "$FIXTURES/defaulted_target_constructor_zero.cr" -o "$binary")
  else
    command=("$SAFE_RUNNER" "$ADAMAS_BIN" 60 8192 "$FIXTURES/defaulted_target_constructor_zero.cr"
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
  printf 'PASS: %s bare/parenthesized/named explicit new output\n' "$mode"
done

for mode in stock lazy eager; do
  binary="$WORK_DIR/negative-$mode.bin"
  if [[ "$mode" == stock ]]; then
    flags=()
    if [[ -n "${ORIGINAL_LINK_FLAGS:-}" ]]; then flags+=("--link-flags=$ORIGINAL_LINK_FLAGS"); fi
    command=("$SAFE_RUNNER" "$CRYSTAL_BIN" 60 4096 build --prelude=empty
      --no-debug --error-trace "${flags[@]}" "$FIXTURES/defaulted_target_bad_type.cr" -o "$binary")
  else
    command=("$SAFE_RUNNER" "$ADAMAS_BIN" 60 8192 "$FIXTURES/defaulted_target_bad_type.cr"
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
     ! grep -Eiq '(no overload matches).*DefaultedReject.value|DefaultedReject.value.*(no overload matches)' \
       "$WORK_DIR/negative.log"; then
    cat "$WORK_DIR/negative.log" >&2
    echo "FAIL: $mode must reject the incompatible defaulted method argument semantically" >&2
    exit 1
  fi
  printf 'PASS: %s incompatible defaulted method argument rejected\n' "$mode"
done
