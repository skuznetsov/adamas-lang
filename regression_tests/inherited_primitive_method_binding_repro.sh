#!/usr/bin/env bash
# Compare inherited primitive source binding with stock Crystal.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
ORIGINAL_ONLY="${ORIGINAL_ONLY:-0}"
[[ "$ORIGINAL_ONLY" == 0 || "$ORIGINAL_ONLY" == 1 ]] || exit 2

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/inherited-primitive-binding.XXXXXX")"
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

export TMPDIR="$WORK_DIR"
export CRYSTAL_CACHE_DIR="$WORK_DIR/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO

original_flags=()
link_flags="${ORIGINAL_LINK_FLAGS:-${ADAMAS_ORIGINAL_LINK_FLAGS:-}}"
[[ -z "$link_flags" ]] || original_flags+=("--link-flags=$link_flags")
modes=(stock)
[[ "$ORIGINAL_ONLY" == 1 ]] || modes+=(lazy eager)

for name in inherited_methods override_result required_arity_shadow nested_factory_tuple numeric_template_self; do
  case "$name" in
    inherited_methods) expected=$'AA\n' ;;
    override_result) expected=$'AB\n' ;;
    required_arity_shadow) expected=$'AB\n' ;;
    nested_factory_tuple) expected=$'C\n' ;;
    numeric_template_self) expected=$'AABB\n' ;;
  esac
  source="$ROOT_DIR/spec/hir/fixtures/inherited_primitive_binding/$name.cr"
  for mode in "${modes[@]}"; do
    key="$name.$mode"
    output="$WORK_DIR/$key.bin"
    compile_status=0
    if [[ "$mode" == stock ]]; then
      "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 120 8192 build "$source" \
        --prelude=empty --no-debug --error-trace "${original_flags[@]}" -o "$output" \
        >"$WORK_DIR/$key.compile.log" 2>&1 || compile_status=$?
    else
      eager_flags=()
      [[ "$mode" != eager ]] || eager_flags=(ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1)
      env "${eager_flags[@]}" "$SAFE_RUNNER" "$ADAMAS_BIN" 120 8192 "$source" \
        --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$output" \
        >"$WORK_DIR/$key.compile.log" 2>&1 || compile_status=$?
    fi
    if [[ "$compile_status" != 0 ]]; then
      cat "$WORK_DIR/$key.compile.log" >&2
      printf 'FAIL: %s did not compile\n' "$key" >&2
      exit 1
    fi

    "$SAFE_RUNNER" "$output" 5 512 >"$WORK_DIR/$key.stdout" 2>"$WORK_DIR/$key.stderr"
    printf '%s' "$expected" >"$WORK_DIR/$key.expected"
    if ! cmp -s "$WORK_DIR/$key.expected" "$WORK_DIR/$key.stdout"; then
      printf 'FAIL: %s produced unexpected output\n' "$key" >&2
      exit 1
    fi
    printf 'PASS: %s\n' "$key"
  done
done

# A concrete receiver must not relax an explicit source argument restriction.
for mode in "${modes[@]}"; do
  key="restricted_argument.$mode"
  source="$ROOT_DIR/spec/hir/fixtures/inherited_primitive_binding/restricted_argument.cr"
  compile_status=0
  if [[ "$mode" == stock ]]; then
    "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 120 8192 build "$source" \
      --prelude=empty --no-debug --error-trace "${original_flags[@]}" -o "$WORK_DIR/$key.bin" \
      >"$WORK_DIR/$key.compile.log" 2>&1 || compile_status=$?
  else
    eager_flags=()
    [[ "$mode" != eager ]] || eager_flags=(ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1)
    env "${eager_flags[@]}" "$SAFE_RUNNER" "$ADAMAS_BIN" 120 8192 "$source" \
      --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$WORK_DIR/$key.bin" \
      >"$WORK_DIR/$key.compile.log" 2>&1 || compile_status=$?
  fi
  if [[ "$compile_status" != 1 ]]; then
    cat "$WORK_DIR/$key.compile.log" >&2
    printf 'FAIL: %s must reject Int64 for Int32 (exit=%s)\n' "$key" "$compile_status" >&2
    exit 1
  fi
  printf 'PASS: %s rejected\n' "$key"
done

# Reusing an abstract Int body must not substitute Int32 for lexical Int
# annotations in nested stdlib calls such as Time::Span.new from milliseconds.
printf 'puts "hello"\n' >"$WORK_DIR/prelude.cr"
prelude_modes=(stock)
[[ "$ORIGINAL_ONLY" == 1 ]] || prelude_modes+=(lazy)
for mode in "${prelude_modes[@]}"; do
  key="prelude.$mode"
  if [[ "$mode" == stock ]]; then
    "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 120 8192 build "$WORK_DIR/prelude.cr" \
      --no-debug --error-trace "${original_flags[@]}" -o "$WORK_DIR/$key.bin" \
      >"$WORK_DIR/$key.compile.log" 2>&1
  else
    "$SAFE_RUNNER" "$ADAMAS_BIN" 120 8192 "$WORK_DIR/prelude.cr" \
      --no-debug --no-ast-cache --no-llvm-cache -o "$WORK_DIR/$key.bin" \
      >"$WORK_DIR/$key.compile.log" 2>&1
  fi
  "$SAFE_RUNNER" "$WORK_DIR/$key.bin" 5 512 >"$WORK_DIR/$key.stdout" 2>"$WORK_DIR/$key.stderr"
  printf 'hello\n' >"$WORK_DIR/$key.expected"
  if ! cmp -s "$WORK_DIR/$key.expected" "$WORK_DIR/$key.stdout"; then
    printf 'FAIL: %s produced unexpected output\n' "$key" >&2
    exit 1
  fi
  printf 'PASS: %s\n' "$key"
done
