#!/usr/bin/env bash
# Resolve nilable constructor arguments against every scalar initializer arm
# before materializing a shared allocator wrapper.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${COMPILER:-${1:-$ROOT_DIR/bin/adamas}}"
POSITIVE_SOURCE="$ROOT_DIR/regression_tests/callnode_union_allocator_repro.cr"
MISSING_SOURCE="$ROOT_DIR/regression_tests/callnode_union_allocator_missing_arm.cr"

if [[ -n "${CRYSTAL_PATH:-}" ]]; then
  STDLIB_PROFILE=explicit
else
  CRYSTAL_PATH="$(crystal env CRYSTAL_PATH)"
  STDLIB_PROFILE=installed
fi
if [[ -z "$CRYSTAL_PATH" ]]; then
  echo "ERROR: could not resolve the selected Crystal standard library" >&2
  exit 2
fi
export CRYSTAL_PATH
printf 'stdlib_profile=%s\nstdlib_path=%s\n' "$STDLIB_PROFILE" "$CRYSTAL_PATH"

if [[ ! -x "$SAFE_RUNNER" || ! -x "$COMPILER" ]]; then
  echo "ERROR: set COMPILER to an executable Adamas compiler" >&2
  exit 2
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/callnode-union-allocator.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == "1" ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

compile_source() {
  local source="$1" output="$2" log="$3"
  local status=0
  CRYSTAL_CACHE_DIR="$WORK_DIR/cache.$(basename "$output")" \
    ADAMAS_LLVM_CACHE=0 \
    "$SAFE_RUNNER" "$COMPILER" 180 6144 "$source" \
      --no-ast-cache --no-llvm-cache -o "$output" >"$log" 2>&1 || status=$?
  if [[ "$status" -ne 0 ]]; then
    echo "FAIL: Adamas compile exited $status for $(basename "$source")" >&2
    tail -30 "$log" >&2
    return 1
  fi
}

run_source() {
  local source="$1" expected="$2" name="$3"
  local output="$WORK_DIR/$name.bin" compile_log="$WORK_DIR/$name.compile.log"
  local run_log="$WORK_DIR/$name.run.log" actual
  compile_source "$source" "$output" "$compile_log"
  # The output parser below expects run_safe's captured STDOUT section.
  RUN_SAFE_PASSTHROUGH_STDIO=0 \
    RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$name.run.resources.json" \
    "$SAFE_RUNNER" "$output" 10 640 >"$run_log" 2>&1 || {
      echo "FAIL: runtime failed for $name" >&2
      cat "$run_log" >&2
      return 1
    }
  actual="$(awk '/^=== STDOUT ===$/{capture=1;next}/^=== STDERR ===$/{capture=0}capture' "$run_log" | tr -d '\r')"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: unexpected output for $name" >&2
    printf 'expected:\n%s\nactual:\n%s\n' "$expected" "$actual" >&2
    return 1
  fi
}

run_source "$POSITIVE_SOURCE" $'both CallNode overloads ok\nwhole-union-nil\nwhole-union-expression\nindirect CallNode overloads ok' callnode-union

missing_output="$WORK_DIR/missing-arm.bin"
missing_log="$WORK_DIR/missing-arm.compile.log"
missing_status=0
CRYSTAL_CACHE_DIR="$WORK_DIR/cache.missing-arm" ADAMAS_LLVM_CACHE=0 \
  "$SAFE_RUNNER" "$COMPILER" 180 6144 "$MISSING_SOURCE" \
    --no-ast-cache --no-llvm-cache -o "$missing_output" >"$missing_log" 2>&1 || missing_status=$?
if [[ "$missing_status" -eq 0 ]]; then
  echo "FAIL: constructor with a missing Nil initializer arm compiled" >&2
  exit 1
fi
if ! rg -q "no overload matches.*IncompleteCallNode\.new" "$missing_log"; then
  echo "FAIL: missing-arm rejection did not report the source overload error" >&2
  tail -30 "$missing_log" >&2
  exit 1
fi
if rg -q "completed initializer ABI disagrees" "$missing_log"; then
  echo "FAIL: missing-arm rejection reached allocator ABI adaptation" >&2
  tail -30 "$missing_log" >&2
  exit 1
fi

echo "PASS: scalar union arms dispatch, whole-union initializer stays selected, missing arm is rejected"
