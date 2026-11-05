#!/usr/bin/env bash
# Non-tuple Allocate constructor fields must use the same inline-byte store
# contract as FieldSet. Compare original Crystal before the candidate.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
REPO_ROOT="${ADAMAS_REPO_ROOT:-$ROOT_DIR}"
SAFE_RUNNER="$REPO_ROOT/scripts/run_safe.sh"
COMPILER="${1:-}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-/opt/homebrew/bin/crystal}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-}"
if [[ -z "$COMPILER" || ! -x "$COMPILER" || ! -x "$ORIGINAL_CRYSTAL_BIN" ]]; then
  echo "ERROR: usage: $0 <candidate-compiler>; original Crystal must be available" >&2
  exit 2
fi
if [[ -z "$CRYSTAL_STDLIB" ]]; then
  CRYSTAL_STDLIB="$(RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 10 512 env CRYSTAL_PATH)"
fi
if [[ ! -x "$SAFE_RUNNER" ]]; then
  echo "ERROR: safe runner not found: $SAFE_RUNNER" >&2
  exit 2
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/allocate-record-inline-field.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" -ne 0 || "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_work=$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

build() {
  local kind="$1" source="$2" mode="$3" output="$4"
  if [[ "$kind" == "original" ]]; then
    if [[ "$mode" == "empty" ]]; then
      env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/original-empty.cache" \
        "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 180 8192 build --prelude=empty "$source" -o "$output"
    else
      env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/original-full.cache" \
        "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 180 8192 build "$source" -o "$output"
    fi
  else
    local flags=(--no-ast-cache --no-llvm-cache)
    if [[ "$mode" == "empty" ]]; then flags+=(--no-prelude); fi
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" ADAMAS_LLVM_CACHE=0 \
      ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}" \
      "$SAFE_RUNNER" "$COMPILER" 180 8192 "$source" "${flags[@]}" -o "$output"
  fi
}

run_and_capture() {
  local kind="$1" expected="$2" output_file="$3" status=0
  "$SAFE_RUNNER" "$WORK_DIR/$kind.bin" 10 512 >"$WORK_DIR/$kind.run.log" 2>&1 || status=$?
  if [[ "$status" -ne 0 ]]; then
    cat "$WORK_DIR/$kind.run.log" >&2
    return 1
  fi
  sed -n '/^=== STDOUT ===$/,/^=== STDERR ===$/{/^=== STDOUT ===$/d;/^=== STDERR ===$/d;p;}' \
    "$WORK_DIR/$kind.run.log" >"$output_file"
  printf '%s' "$expected" >"$WORK_DIR/expected.stdout"
  diff -u "$WORK_DIR/expected.stdout" "$output_file"
}

positive() {
  local source="$1" mode="$2" expected="$3"
  for kind in original candidate; do
    local log="$WORK_DIR/$kind.$mode.build.log"
    if ! build "$kind" "$source" "$mode" "$WORK_DIR/$kind.bin" >"$log" 2>&1; then
      cat "$log" >&2
      return 1
    fi
    run_and_capture "$kind" "$expected" "$WORK_DIR/$kind.stdout"
  done
}

positive "$ROOT_DIR/regression_tests/allocate_record_inline_field_no_prelude.cr" empty $'A\n'
positive "$ROOT_DIR/regression_tests/allocate_record_inline_field_full_prelude.cr" full $'range_constructor_inline_field_ok\n'
echo "PASS: record Allocate inline-field stores match original Crystal"
