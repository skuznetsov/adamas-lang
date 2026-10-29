#!/usr/bin/env bash
# Verify that a user-defined positional spawn method keeps its own body when
# its mangled name has the spawn$$..._block shape used by the stdlib overload.
# A named-argument variant is included as a control outside that exact suffix.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
SAFE_RUNNER="$REPO_ROOT/scripts/run_safe.sh"

if [ "$#" -gt 1 ]; then
  echo "usage: $0 [candidate_compiler]" >&2
  exit 2
fi

ORIGINAL_CRYSTAL="${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}"
CANDIDATE_COMPILER="${1:-$REPO_ROOT/bin/adamas}"
CLANG_BIN="${CLANG_BIN:-$(command -v clang || true)}"

for tool in "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL" "$CANDIDATE_COMPILER"; do
  if [ ! -x "$tool" ]; then
    echo "required executable is missing: $tool" >&2
    exit 2
  fi
done
if [ -z "$CLANG_BIN" ] || [ ! -x "$CLANG_BIN" ]; then
  echo "clang is required to build the callback-effect helper" >&2
  exit 2
fi

if [ -z "${CRYSTAL_PATH:-}" ]; then
  CRYSTAL_PATH="$(RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL" 10 1024 env CRYSTAL_PATH)"
fi
export CRYSTAL_PATH

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/source-spawn-body.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

HELPER_SOURCE="$WORK_DIR/helper.c"
HELPER_OBJECT="$WORK_DIR/helper.o"
SOURCE_NAMED="$WORK_DIR/named_control.cr"
SOURCE_POSITIONAL="$WORK_DIR/positional_probe.cr"

cat >"$HELPER_SOURCE" <<'C'
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static int32_t callback_effect;

void adamas_spawn_record_callback(int32_t value) {
  callback_effect = value;
}

int32_t adamas_spawn_check(int32_t result) {
  int32_t status = (result == 42 && callback_effect == 73) ? 0 : 1;
  printf("spawn_result=%d callback_effect=%d status=%d\n",
      result, callback_effect, status);
  fflush(stdout);
  return status;
}

void adamas_spawn_exit(int32_t status) {
  _Exit(status);
}
C

write_source() {
  local mode="$1"
  local path="$2"
  cat >"$path" <<'CR'
require "primitives"
require "proc"

@[Link("gc", pkg_config: "bdw-gc")]
lib LibGC
end

lib SpawnBodyProbe
  fun record_callback = adamas_spawn_record_callback(value : Int32) : Void
  fun check = adamas_spawn_check(result : Int32) : Int32
  fun exit = adamas_spawn_exit(status : Int32) : NoReturn
end

# The original no-prelude compiler emits a closure-conversion guard for a
# stored block Proc. A valid non-capturing callback must never reach this trap.
def raise(message : String) : NoReturn
  SpawnBodyProbe.exit(93)
end

@[NoInline]
CR
  if [ "$mode" = named ]; then
    cat >>"$path" <<'CR'
def spawn(*, name : String, same_thread : Bool, &block : -> Int32) : Int32
CR
  else
    cat >>"$path" <<'CR'
def spawn(name : String, same_thread : Bool, &block : -> Int32) : Int32
CR
  fi
  cat >>"$path" <<'CR'
  saved_callback = block
  if same_thread
    saved_callback.call
  else
    0_i32
  end
end

CR
  if [ "$mode" = named ]; then
    cat >>"$path" <<'CR'
result = spawn(name: "user-defined", same_thread: true) do
CR
  else
    cat >>"$path" <<'CR'
result = spawn("user-defined", true) do
CR
  fi
  cat >>"$path" <<'CR'
  SpawnBodyProbe.record_callback(73_i32)
  42_i32
end
SpawnBodyProbe.exit(SpawnBodyProbe.check(result))
CR
}

write_source named "$SOURCE_NAMED"
write_source positional "$SOURCE_POSITIONAL"

echo "Building C callback-effect helper with $CLANG_BIN"
"$SAFE_RUNNER" "$CLANG_BIN" 120 4096 -std=c11 -Wall -Wextra -Werror -O0 \
  -c "$HELPER_SOURCE" -o "$HELPER_OBJECT"

compile_and_run() {
  local label="$1"
  local compiler="$2"
  local output_bin="$3"
  local source="$4"
  local build_log="$WORK_DIR/$label.build.log"
  local run_log="$WORK_DIR/$label.run.log"

  echo "Compiling with $label: $compiler"
  if [[ "$label" == original_* ]]; then
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/$label-cache" \
      "$SAFE_RUNNER" "$compiler" 180 8192 build "$source" \
      --prelude=empty -o "$output_bin" "--link-flags=$HELPER_OBJECT" \
      >"$build_log" 2>&1; then
      printf '%s_build_status=failed\n' "$label" >&2
      cat "$build_log" >&2
      return 1
    fi
  else
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/$label-cache" \
      ADAMAS_EXTRA_LINK_FLAGS="$HELPER_OBJECT" \
      "$SAFE_RUNNER" "$compiler" 180 8192 "$source" \
      --prelude=empty -o "$output_bin" >"$build_log" 2>&1; then
      printf '%s_build_status=failed\n' "$label" >&2
      cat "$build_log" >&2
      return 1
    fi
  fi
  printf '%s_build_status=0\n' "$label"

  if ! "$SAFE_RUNNER" "$output_bin" 10 512 >"$run_log" 2>&1; then
    printf '%s_run_status=failed\n' "$label" >&2
    cat "$run_log" >&2
    return 1
  fi
  printf '%s_run_status=0\n' "$label"
  cat "$run_log"
  if ! grep -Fxq 'spawn_result=42 callback_effect=73 status=0' "$run_log"; then
    printf '%s did not preserve the source spawn body and callback result\n' "$label" >&2
    return 1
  fi
}

# Qualify both source shapes against the original before running the candidate.
compile_and_run original_named "$ORIGINAL_CRYSTAL" "$WORK_DIR/original-named.bin" "$SOURCE_NAMED"
compile_and_run original_positional "$ORIGINAL_CRYSTAL" "$WORK_DIR/original-positional.bin" "$SOURCE_POSITIONAL"

overall_status=0
if ! compile_and_run candidate_named "$CANDIDATE_COMPILER" "$WORK_DIR/candidate-named.bin" "$SOURCE_NAMED"; then
  overall_status=1
fi
if ! compile_and_run candidate_positional "$CANDIDATE_COMPILER" "$WORK_DIR/candidate-positional.bin" "$SOURCE_POSITIONAL"; then
  overall_status=1
fi

if [ "$overall_status" -ne 0 ]; then
  echo "FAIL: candidate differs from the original on a user-defined spawn body" >&2
  exit "$overall_status"
fi

echo "PASS: original and candidate preserve user-defined spawn body, callback effect, and Int32 result"
