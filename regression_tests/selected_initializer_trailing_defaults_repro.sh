#!/usr/bin/env bash
# Differential regression for exact selected initializer trailing defaults.
# Run as: regression_tests/selected_initializer_trailing_defaults_repro.sh /path/to/adamas
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADAMAS_BIN="${1:-$ROOT_DIR/bin/adamas}"
CRYSTAL_BIN="${CRYSTAL_BIN:-$(command -v crystal)}"
export RUN_SAFE_PASSTHROUGH_STDIO=1
if [[ -z "${CRYSTAL_PATH:-}" ]]; then
  CRYSTAL_PATH="$("$CRYSTAL_BIN" env CRYSTAL_PATH)"
  export CRYSTAL_PATH
fi
FIXTURES="$ROOT_DIR/regression_tests/fixtures/selected_initializer_trailing_defaults"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/selected_init_defaults.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

compile_adamas() {
  local name="$1" source="$2"
  "$ROOT_DIR/scripts/run_safe.sh" "$ADAMAS_BIN" 300 8192 "$source" \
    -o "$WORK_DIR/adamas-$name" >"$WORK_DIR/adamas-$name.build.log" 2>&1 || {
      echo "Adamas compile failed: $name" >&2
      tail -40 "$WORK_DIR/adamas-$name.build.log" >&2
      return 1
    }
}

run_adamas() {
  local name="$1" expected="$2"
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/adamas-$name" 10 1024 \
    >"$WORK_DIR/adamas-$name.out" 2>"$WORK_DIR/adamas-$name.run.log" || {
      echo "Adamas run failed: $name" >&2
      cat "$WORK_DIR/adamas-$name.run.log" >&2
      return 1
    }
  printf '%s\n' "$expected" >"$WORK_DIR/expected-$name.out"
  diff -u "$WORK_DIR/expected-$name.out" "$WORK_DIR/adamas-$name.out"
}

expect_adamas_rejection() {
  local name="$1" pattern="$2" source="$3"
  if "$ROOT_DIR/scripts/run_safe.sh" "$ADAMAS_BIN" 300 8192 "$source" \
      -o "$WORK_DIR/adamas-$name" >"$WORK_DIR/adamas-$name.reject.log" 2>&1; then
    echo "Adamas unexpectedly accepted: $name" >&2
    return 1
  fi
  if ! grep -Eiq "$pattern" "$WORK_DIR/adamas-$name.reject.log"; then
    echo "Adamas rejection had the wrong diagnostic: $name" >&2
    tail -40 "$WORK_DIR/adamas-$name.reject.log" >&2
    return 1
  fi
}

compile_adamas omitted "$FIXTURES/positive.cr"
run_adamas omitted $'6\n5\n25\n0\n18\n0\n18\n0\n3'
compile_adamas overload "$FIXTURES/overload_source_binding.cr"
run_adamas overload $'11\n22\n33\n2'
compile_adamas runtime_union "$ROOT_DIR/regression_tests/allocator_runtime_union_trailing_defaults.cr"
run_adamas runtime_union "four parameter shapes ok"

expect_adamas_rejection missing_required 'no overload matches|missing argument' \
  "$FIXTURES/missing_required.cr"
expect_adamas_rejection invalid_actual 'no overload matches|expected argument|type mismatch' \
  "$FIXTURES/invalid_actual.cr"
expect_adamas_rejection invalid_default "can't restrict String to Int32|expected argument.*Int32" \
  "$FIXTURES/invalid_default.cr"

compile_crystal() {
  local name="$1" source="$2"
  "$ROOT_DIR/scripts/run_safe.sh" "$CRYSTAL_BIN" 300 8192 build "$source" \
    -o "$WORK_DIR/crystal-$name" >"$WORK_DIR/crystal-$name.build.log" 2>&1 || {
      echo "Crystal oracle compile failed: $name" >&2
      tail -40 "$WORK_DIR/crystal-$name.build.log" >&2
      return 1
    }
}
run_crystal() {
  local name="$1" expected="$2"
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/crystal-$name" 10 1024 \
    >"$WORK_DIR/crystal-$name.out" 2>"$WORK_DIR/crystal-$name.run.log" || {
      echo "Crystal oracle run failed: $name" >&2
      cat "$WORK_DIR/crystal-$name.run.log" >&2
      return 1
    }
  printf '%s\n' "$expected" >"$WORK_DIR/crystal-expected-$name.out"
    diff -u "$WORK_DIR/crystal-expected-$name.out" "$WORK_DIR/crystal-$name.out"
}
expect_crystal_rejection() {
  local name="$1" pattern="$2" source="$3"
  if "$ROOT_DIR/scripts/run_safe.sh" "$CRYSTAL_BIN" 300 8192 build "$source" \
      -o "$WORK_DIR/crystal-$name" >"$WORK_DIR/crystal-$name.reject.log" 2>&1; then
    echo "Crystal unexpectedly accepted: $name" >&2
    return 1
  fi
  if ! grep -Eiq "$pattern" "$WORK_DIR/crystal-$name.reject.log"; then
    echo "Crystal rejection had the wrong diagnostic: $name" >&2
    tail -40 "$WORK_DIR/crystal-$name.reject.log" >&2
    return 1
  fi
}

compile_crystal omitted "$FIXTURES/positive.cr"
run_crystal omitted $'6\n5\n25\n0\n18\n0\n18\n0\n3'
compile_crystal overload "$FIXTURES/overload_source_binding.cr"
run_crystal overload $'11\n22\n33\n2'
compile_crystal runtime_union "$ROOT_DIR/regression_tests/allocator_runtime_union_trailing_defaults.cr"
run_crystal runtime_union "four parameter shapes ok"
expect_crystal_rejection missing_required 'missing argument|wrong number of arguments|no overload matches' \
  "$FIXTURES/missing_required.cr"
expect_crystal_rejection invalid_actual 'no overload matches|expected argument|type mismatch' \
  "$FIXTURES/invalid_actual.cr"
expect_crystal_rejection invalid_default "can't restrict String to Int32|expected argument.*Int32" \
  "$FIXTURES/invalid_default.cr"

echo selected_initializer_trailing_defaults_repro_ok
