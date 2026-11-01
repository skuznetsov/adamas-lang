#!/usr/bin/env bash
# Exercise source-applied include selection in lazy and eager HIR modes.
# Optional CRYSTAL_BIN qualifies the same expected bytes against stock Crystal.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ADAMAS_ROOT="$ROOT_DIR"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
SAFE_RUN="${SAFE_RUNNER:-$ROOT_DIR/scripts/run_safe.sh}"
FIXTURE_DIR="$ROOT_DIR/regression_tests/fixtures/source_applied_include_contract"

if [[ ! -x "$SAFE_RUN" || ! -x "$COMPILER" ]]; then
  echo "expected executable safe runner and Adamas compiler under $ADAMAS_ROOT" >&2
  exit 2
fi

fixtures=(
  getter_then_splat.cr
  hook_class_macro_include.cr
  hook_def_then_include.cr
  hook_generic_applied_include.cr
  hook_getter_then_include.cr
  hook_hook_source_order.cr
  hook_include_then_def.cr
  hook_include_then_getter.cr
  nested_generic_callback_include.cr
  nested_super_context.cr
  noarg_annotated.cr
  noarg_inferred.cr
  noarg_parenthesized.cr
  own_formal_shadow.cr
  receiver_owned_override.cr
  rooted_application.cr
  splat_then_getter.cr
  transitive_generic_callback_include.cr
  tuple_block_input.cr
  yield_then_getter.cr
)
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/source_applied_include.XXXXXX")"
trap 'rm -rf -- "$WORK_DIR"' EXIT

run_and_compare() {
  local label="$1"
  local binary="$2"
  local expected="$3"
  local actual="$4"
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUN" "$binary" 5 512 >"$actual" 2>"$WORK_DIR/run.log"; then
    cat "$WORK_DIR/run.log" >&2
    echo "FAIL: $label did not run safely" >&2
    return 1
  fi
  if ! cmp -s "$expected" "$actual"; then
    echo "FAIL: $label stdout differs from its expected bytes" >&2
    echo "expected:" >&2
    od -An -tx1 "$expected" >&2
    echo "actual:" >&2
    od -An -tx1 "$actual" >&2
    return 1
  fi
}

for mode in lazy eager; do
  env_args=(-u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
  if [[ "$mode" == eager ]]; then
    env_args+=(ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1)
  fi

  for fixture in "${fixtures[@]}"; do
    source="$FIXTURE_DIR/$fixture"
    expected="$FIXTURE_DIR/${fixture%.cr}.expected.stdout"
    binary="$WORK_DIR/${fixture%.cr}.$mode"
    if ! env "${env_args[@]}" "$SAFE_RUN" "$COMPILER" 120 8192 \
        "$source" --no-prelude --no-debug --no-ast-cache --no-llvm-cache \
        -o "$binary" >"$WORK_DIR/build.log" 2>&1; then
      cat "$WORK_DIR/build.log" >&2
      echo "FAIL: $fixture did not compile in $mode mode" >&2
      exit 1
    fi
    run_and_compare "$fixture ($mode)" "$binary" "$expected" "$WORK_DIR/actual"
  done
done

if [[ -n "${CRYSTAL_BIN:-}" ]]; then
  if [[ ! -x "$CRYSTAL_BIN" ]]; then
    echo "CRYSTAL_BIN is not executable: $CRYSTAL_BIN" >&2
    exit 2
  fi
  for fixture in "${fixtures[@]}"; do
    source="$FIXTURE_DIR/$fixture"
    expected="$FIXTURE_DIR/${fixture%.cr}.expected.stdout"
    binary="$WORK_DIR/${fixture%.cr}.stock"
    if ! "$SAFE_RUN" "$CRYSTAL_BIN" 120 8192 build "$source" \
        --prelude=empty --no-debug -o "$binary" >"$WORK_DIR/stock-build.log" 2>&1; then
      cat "$WORK_DIR/stock-build.log" >&2
      echo "FAIL: $fixture did not compile with CRYSTAL_BIN" >&2
      exit 1
    fi
    run_and_compare "$fixture (CRYSTAL_BIN)" "$binary" "$expected" "$WORK_DIR/actual"
  done
fi

echo "PASS: source-applied include outputs match in lazy and eager modes"
