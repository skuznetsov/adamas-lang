#!/usr/bin/env bash
# Validate recursive macro type receivers without expanding alias cycles forever.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-/opt/homebrew/bin/crystal}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-/Users/sergey/Projects/Crystal/crystal/src}"
[[ -x "$COMPILER" && -x "$ORIGINAL_CRYSTAL_BIN" && -x "$SAFE_RUNNER" && -d "$CRYSTAL_STDLIB" ]] || {
  echo "usage: $0 <candidate-compiler>" >&2
  exit 2
}

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macro-recursive-type-receiver.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf "$WORK_DIR/original.cache" "$WORK_DIR/candidate.cache"
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cp "$ROOT_DIR/regression_tests/fixtures/macro_recursive_type_receiver.cr" "$WORK_DIR/probe.cr"

compile_and_run() {
  local producer="$1"
  local compiler="$2"
  shift 2
  local bin="$WORK_DIR/$producer.bin"
  local cache_dir="$WORK_DIR/$producer.cache"
  local compile_log="$WORK_DIR/$producer.compile.log"
  local run_log="$WORK_DIR/$producer.run.log"
  local status=0

  mkdir -p "$cache_dir"
  if [[ "$producer" == original ]]; then
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache_dir" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$producer.compile.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 build "$WORK_DIR/probe.cr" --no-debug \
      -o "$bin" --link-flags=-fuse-ld=/usr/bin/ld >"$compile_log" 2>&1 || status=$?
  else
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache_dir" \
      ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS=-fuse-ld=/usr/bin/ld \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$producer.compile.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 "$WORK_DIR/probe.cr" --no-prelude \
      --no-ast-cache --no-llvm-cache --no-debug -o "$bin" >"$compile_log" 2>&1 || status=$?
  fi
  if [[ "$status" != 0 ]]; then
    cat "$compile_log" >&2
    return "$status"
  fi

  status=0
  RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$producer.run.resources" \
    "$SAFE_RUNNER" "$bin" 15 512 >"$run_log" 2>&1 || status=$?
  if [[ "$status" != 0 ]] || ! grep -Fq '[EXIT: 0]' "$run_log"; then
    cat "$run_log" >&2
    return 1
  fi
}

compile_and_run original "$ORIGINAL_CRYSTAL_BIN"
compile_and_run candidate "$COMPILER"
printf 'PASS: original and candidate agree on recursive alias and generic macro receiver checks\n'
