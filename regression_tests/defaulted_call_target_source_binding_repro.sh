#!/usr/bin/env bash
# Default expansion must retain the exact selected source and reject bad types.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
ORIGINAL_ONLY="${ORIGINAL_ONLY:-0}"
[[ "$ORIGINAL_ONLY" == 0 || "$ORIGINAL_ONLY" == 1 ]] || exit 2
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/defaulted-call-target.XXXXXX")"
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
  "$SAFE_RUNNER" "$WORK_DIR/$key.bin" 5 512 >"$WORK_DIR/$key.stdout" 2>"$WORK_DIR/$key.stderr"
  printf '%s' "$expected" >"$WORK_DIR/$key.expected"
  if ! cmp -s "$WORK_DIR/$key.expected" "$WORK_DIR/$key.stdout"; then
    printf 'FAIL: %s produced unexpected output\n' "$key" >&2
    exit 1
  fi
  printf 'PASS: %s\n' "$key"
}
for name in named_scalar named_tuple positional_tuple class_member instance_member struct_member overload; do
  case "$name" in
    named_scalar|named_tuple|positional_tuple) expected=A ;;
    class_member|instance_member|struct_member) expected=$'A\n' ;;
    overload) expected=ABX ;;
  esac
  source="$ROOT_DIR/regression_tests/fixtures/defaulted_call_target/defaulted_target_$name.cr"
  for mode in "${modes[@]}"; do
    key="$name.$mode"
    if ! compile "$source" "$mode" "$WORK_DIR/$key.bin" empty >"$WORK_DIR/$key.compile.log" 2>&1; then
      cat "$WORK_DIR/$key.compile.log" >&2
      exit 1
    fi
    check_output "$key" "$expected"
  done
done
for mode in "${modes[@]}"; do
  key="bad_type.$mode"
  status=0
  compile "$ROOT_DIR/regression_tests/fixtures/defaulted_call_target/defaulted_target_bad_type.cr" \
    "$mode" "$WORK_DIR/$key.bin" empty >"$WORK_DIR/$key.compile.log" 2>&1 || status=$?
  if [[ "$status" != 1 ]] || ! grep -Fq 'no overload' "$WORK_DIR/$key.compile.log" || \
      ! grep -Fq 'DefaultedReject.value' "$WORK_DIR/$key.compile.log" || \
      ! grep -Fq 'Int64' "$WORK_DIR/$key.compile.log"; then
    cat "$WORK_DIR/$key.compile.log" >&2
    printf 'FAIL: %s did not reject the Int64 argument as an overload mismatch\n' "$key" >&2
    exit 1
  fi
  printf 'PASS: %s rejected\n' "$key"
done

# Exact default-target binding must preserve unchanged stdlib compilation.
printf 'puts "hello"\n' >"$WORK_DIR/prelude.cr"
prelude_modes=(stock)
[[ "$ORIGINAL_ONLY" == 1 ]] || prelude_modes+=(lazy)
for mode in "${prelude_modes[@]}"; do
  key="prelude.$mode"
  if ! compile "$WORK_DIR/prelude.cr" "$mode" "$WORK_DIR/$key.bin" stock >"$WORK_DIR/$key.compile.log" 2>&1; then
    cat "$WORK_DIR/$key.compile.log" >&2
    exit 1
  fi
  check_output "$key" $'hello\n'
done
