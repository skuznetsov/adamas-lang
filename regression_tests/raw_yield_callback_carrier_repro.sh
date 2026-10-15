#!/usr/bin/env bash
# Pass a proven null-environment Proc through a raw yield callback formal.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-/opt/homebrew/bin/crystal}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-/Users/sergey/Projects/Crystal/crystal/src}"
CC="${CC:-/usr/bin/cc}"
[[ -x "$ADAMAS_BIN" && -x "$ORIGINAL_CRYSTAL" && -x "$SAFE_RUNNER" && -d "$CRYSTAL_STDLIB" ]] || {
  echo "usage: ADAMAS_BIN=<compiler> $0" >&2
  exit 2
}

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/raw-yield-callback-carrier.XXXXXX")"
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

cat >"$WORK_DIR/probe.c" <<'C'
#include <stdint.h>
#include <stdio.h>

static int32_t context_token;
static int32_t calls;
static int32_t null_context_calls;
static int32_t expected_context_calls;
static int32_t unexpected_context_calls;

static void null_context_callback(void) {
  calls++;
  null_context_calls++;
}

static void nonnull_context_callback(void *context) {
  calls++;
  if (context == &context_token) expected_context_calls++;
  else unexpected_context_calls++;
}

void *null_context_callback_address(void) {
  return (void *)null_context_callback;
}

void *nonnull_context_callback_address(void) {
  return (void *)nonnull_context_callback;
}

void *null_context_address(void) {
  return 0;
}

void *nonnull_context_address(void) {
  return &context_token;
}

int32_t raw_callback_status(void) {
  fprintf(stderr, "status=%d,%d,%d,%d\n", calls, null_context_calls,
      expected_context_calls, unexpected_context_calls);
  return calls * 1000 + null_context_calls * 100 +
      expected_context_calls * 10 + unexpected_context_calls;
}
C

cat >"$WORK_DIR/probe.cr" <<'CRYSTAL'
require "primitives"
require "proc"
require "pointer"

lib RawProcPairProbe
  fun null_context_callback_address : Void*
  fun nonnull_context_callback_address : Void*
  fun null_context_address : Void*
  fun nonnull_context_address : Void*
  fun raw_callback_status : Int32
end

@[NoInline]
def invoke_raw_callback(& : -> Nil)
  yield
end

fun main(argc : Int32, argv : UInt8**) : Int32
  invoke_raw_callback(&Proc(Nil).new(RawProcPairProbe.null_context_callback_address, Pointer(Void).null))
  Proc(Nil).new(RawProcPairProbe.nonnull_context_callback_address, RawProcPairProbe.nonnull_context_address).call
  status = RawProcPairProbe.raw_callback_status
  status == 2110 ? 0 : 1
end
CRYSTAL

run_checked() {
  local name="$1"
  shift
  if ! RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$name.resources" \
      "$SAFE_RUNNER" "$@" >"$WORK_DIR/$name.log" 2>&1; then
    cat "$WORK_DIR/$name.log" >&2
    return 1
  fi
}

run_checked c-build "$CC" 30 512 -c "$WORK_DIR/probe.c" -o "$WORK_DIR/probe.o"

env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/original.cache" \
  RUN_SAFE_RESOURCE_FILE="$WORK_DIR/original-build.resources" \
  "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL" 180 8192 build "$WORK_DIR/probe.cr" \
  -o "$WORK_DIR/original" \
  "--link-flags=$WORK_DIR/probe.o -fuse-ld=/usr/bin/ld" \
  >"$WORK_DIR/original-build.log" 2>&1 || {
    cat "$WORK_DIR/original-build.log" >&2
    exit 1
  }
rm -rf "$WORK_DIR/original.cache"

env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/candidate.cache" \
  ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS="$WORK_DIR/probe.o -fuse-ld=/usr/bin/ld" \
  RUN_SAFE_RESOURCE_FILE="$WORK_DIR/candidate-build.resources" \
  "$SAFE_RUNNER" "$ADAMAS_BIN" 180 8192 "$WORK_DIR/probe.cr" --no-prelude \
  --no-ast-cache --no-llvm-cache -o "$WORK_DIR/candidate" \
  >"$WORK_DIR/candidate-build.log" 2>&1 || {
    cat "$WORK_DIR/candidate-build.log" >&2
    exit 1
  }
rm -rf "$WORK_DIR/candidate.cache"

for stage in original candidate; do
  if ! RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stage-run.resources" \
      "$SAFE_RUNNER" "$WORK_DIR/$stage" 10 512 \
      >"$WORK_DIR/$stage-run.log" 2>&1; then
    cat "$WORK_DIR/$stage-run.log" >&2
    exit 1
  fi
  grep -Fq '[EXIT: 0]' "$WORK_DIR/$stage-run.log" || {
    cat "$WORK_DIR/$stage-run.log" >&2
    printf '%s did not preserve both raw Proc context pointers\n' "$stage" >&2
    exit 1
  }
done

printf 'PASS: raw yield callback runs once and preserves the non-null Proc context\n'
