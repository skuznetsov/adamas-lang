#!/usr/bin/env bash
# Two direct, explicitly typed Proc literals passed through the same C formal
# must retain distinct generated callback function identities and bodies.
# Before the fix, both lowered to one fixed name and create_function reused its
# existing Function, so this output could not retain both independent bodies.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <candidate-compiler>" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
SAFE_RUNNER="${ADAMAS_RUN_SAFE:-$ROOT_DIR/scripts/run_safe.sh}"
COMPILER="$1"
CC="${CC:-/usr/bin/cc}"
[[ -x "$COMPILER" && -x "$SAFE_RUNNER" && -x "$CC" ]] || {
  echo "candidate compiler, C compiler, or safe runner is unavailable" >&2
  exit 2
}

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/adamas_c_callback_site_identity.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
  return "$status"
}
trap cleanup EXIT

BRIDGE_OBJ="$WORK_DIR/c_callback_site_identity_shim.o"
BIN="$WORK_DIR/c_callback_site_identity"
BUILD_LOG="$WORK_DIR/build.log"
RUN_LOG="$WORK_DIR/run.log"
FIXTURE="$SCRIPT_DIR/c_callback_site_identity_repro.cr"
BRIDGE="$WORK_DIR/c_callback_site_identity.c"

# Keep this C shim in the test script because regression_tests ignores standalone
# .c files. The checked-in Crystal fixture remains the source-level oracle.
cat >"$BRIDGE" <<'C'
#include <stdint.h>
#include <stdio.h>

typedef void (*adamas_callback)(int32_t, const uint8_t *);

void adamas_callback_site_invoke(adamas_callback callback) {
  static const uint8_t payload[] = {'B', 0};
  callback(65, payload);
}

void adamas_callback_site_emit_first(int32_t code, const uint8_t *payload) {
  putchar((unsigned char)code);
  putchar((unsigned char)payload[0]);
  putchar('\n');
}

void adamas_callback_site_emit_second(int32_t code, const uint8_t *payload) {
  putchar((unsigned char)(code + 1));
  putchar((unsigned char)payload[0]);
  putchar('\n');
}
C

"$CC" -std=c11 -Wall -Wextra -Werror -c "$BRIDGE" -o "$BRIDGE_OBJ"

LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:-}"
if [[ -n "$LINK_FLAGS" ]]; then
  LINK_FLAGS+=" $BRIDGE_OBJ"
else
  LINK_FLAGS="$BRIDGE_OBJ"
fi

ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS="$LINK_FLAGS" \
  "$SAFE_RUNNER" "$COMPILER" 120 4096 "$FIXTURE" \
    --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$BIN" \
    >"$BUILD_LOG" 2>&1 || {
      cat "$BUILD_LOG" >&2
      exit 1
    }

"$SAFE_RUNNER" "$BIN" 10 512 >"$RUN_LOG" 2>&1 || {
  cat "$RUN_LOG" >&2
  exit 1
}

actual="$(awk '/^=== STDOUT ===/{capture=1; next} /^=== STDERR ===/{capture=0} capture {print}' "$RUN_LOG" | tr -d '\r')"
expected=$'AB\nBB'
if [[ "$actual" != "$expected" ]]; then
  echo "callback site identity regression: expected two distinct bodies" >&2
  printf 'expected:\n%s\nactual:\n%s\n' "$expected" "$actual" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

echo "c_callback_site_identity_ok"
