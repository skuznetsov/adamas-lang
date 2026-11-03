#!/usr/bin/env bash
# Preserve numeric generic value kinds and widths during instance dispatch.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
ORIGINAL_ONLY="${ORIGINAL_ONLY:-0}"
[[ "$ORIGINAL_ONLY" == 0 || "$ORIGINAL_ONLY" == 1 ]] || exit 2
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/generic-value-receiver-self.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf -- "$WORK_DIR/cache"
  if [[ "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf -- "$WORK_DIR"
  fi
  exit "$status"
}
trap cleanup EXIT
export TMPDIR="$WORK_DIR" CRYSTAL_CACHE_DIR="$WORK_DIR/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
link_flags="${ORIGINAL_LINK_FLAGS:-${ADAMAS_ORIGINAL_LINK_FLAGS:-}}"
[[ -z "$link_flags" ]] || original_flags+=("--link-flags=$link_flags")
modes=(stock)
[[ "$ORIGINAL_ONLY" == 1 ]] || modes+=(lazy eager)

compile() {
  local source="$1" mode="$2" output="$3" prelude="$4"
  if [[ "$mode" == stock ]]; then
    local prelude_flags=()
    [[ "$prelude" == stock ]] || prelude_flags=(--prelude=empty)
    "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 120 8192 build "$source" \
      "${prelude_flags[@]}" --no-debug --error-trace "${original_flags[@]}" -o "$output"
  else
    local prelude_flags=() eager_flags=()
    [[ "$prelude" == stock ]] || prelude_flags=(--no-prelude)
    [[ "$mode" != eager ]] || eager_flags=(ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1)
    env "${eager_flags[@]}" "$SAFE_RUNNER" "$ADAMAS_BIN" 120 8192 "$source" \
      "${prelude_flags[@]}" --no-debug --no-ast-cache --no-llvm-cache -o "$output"
  fi
}
check_output() {
  local key="$1" expected="$2"
  local status=0
  "$SAFE_RUNNER" "$WORK_DIR/$key.bin" 5 512 >"$WORK_DIR/$key.stdout" 2>"$WORK_DIR/$key.stderr" || status=$?
  if [[ "$status" != 0 ]]; then
    cat "$WORK_DIR/$key.stderr" >&2
    printf 'FAIL: %s exited %s\n' "$key" "$status" >&2
    exit "$status"
  fi
  printf '%s' "$expected" >"$WORK_DIR/$key.expected"
  if ! cmp -s "$WORK_DIR/$key.expected" "$WORK_DIR/$key.stdout"; then
    printf 'FAIL: %s produced unexpected output\n' "$key" >&2
    exit 1
  fi
  printf 'PASS: %s\n' "$key"
}
for name in int32_receiver int64_receiver type_parameter_class_receiver direct_literal_receiver; do
  source="$ROOT_DIR/regression_tests/fixtures/generic_value_receiver_self/$name.cr"
  for mode in "${modes[@]}"; do
    key="$name.$mode"
    if ! compile "$source" "$mode" "$WORK_DIR/$key.bin" empty >"$WORK_DIR/$key.compile.log" 2>&1; then
      cat "$WORK_DIR/$key.compile.log" >&2
      exit 1
    fi
    check_output "$key" $'A\n'
  done
done
for mode in "${modes[@]}"; do
  key="int64_receiver_int32_block.$mode"
  status=0
  compile "$ROOT_DIR/regression_tests/fixtures/generic_value_receiver_self/int64_receiver_int32_block.cr" \
    "$mode" "$WORK_DIR/$key.bin" empty >"$WORK_DIR/$key.compile.log" 2>&1 || status=$?
  if [[ "$status" != 1 ]] || ! grep -Eq 'expected|block|Proc|no overload' "$WORK_DIR/$key.compile.log"; then
    cat "$WORK_DIR/$key.compile.log" >&2
    printf 'FAIL: %s did not reject the callback width mismatch\n' "$key" >&2
    exit 1
  fi
  printf 'PASS: %s rejected\n' "$key"
done
