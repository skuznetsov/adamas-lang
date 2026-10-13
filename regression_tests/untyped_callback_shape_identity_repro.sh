#!/usr/bin/env bash
# No-prelude semantic oracle for untyped raw-yield callback shape identity.
# The same regular callee receives the same actual union argument shape, while
# its callbacks return different concrete types. Both discovery orders must
# preserve the callback contract instead of reusing the first raw ABI.
# CALLBACK_RECEIVER=1 switches the identical callee pair to instance methods,
# covering receiver dispatch used by Tuple#reduce-style call paths.
# CALLBACK_MODULE=1 covers module-owned class methods.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
ORIGINAL_CRYSTAL="${ORIGINAL_CRYSTAL:-crystal}"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"
TIMEOUT_SECS="${UNTYPED_CALLBACK_SHAPE_TIMEOUT:-5}"
MAX_MEM_MB="${UNTYPED_CALLBACK_SHAPE_MAX_MEM:-512}"
COMPILE_TIMEOUT_SECS="${UNTYPED_CALLBACK_SHAPE_COMPILE_TIMEOUT:-120}"
COMPILE_MAX_MEM_MB="${UNTYPED_CALLBACK_SHAPE_COMPILE_MAX_MEM:-8192}"
EXPECT_MISMATCH="${ADAMAS_EXPECT_UNTYPED_CALLBACK_SHAPE_MISMATCH:-0}"
CALLBACK_RECEIVER="${CALLBACK_RECEIVER:-0}"
CALLBACK_MODULE="${CALLBACK_MODULE:-0}"

if [[ "$CALLBACK_RECEIVER" != "0" && "$CALLBACK_RECEIVER" != "1" ]]; then
  echo "ERROR: CALLBACK_RECEIVER must be 0 or 1" >&2
  exit 2
fi
if [[ "$CALLBACK_MODULE" != "0" && "$CALLBACK_MODULE" != "1" ]] ||
   [[ "$CALLBACK_MODULE" == "1" && "$CALLBACK_RECEIVER" == "1" ]]; then
  echo "ERROR: CALLBACK_MODULE must be 0 or 1 and excludes CALLBACK_RECEIVER=1" >&2
  exit 2
fi
if [[ "$CALLBACK_MODULE" == "1" ]]; then
  CALLBACK_MODE="module class method"
elif [[ "$CALLBACK_RECEIVER" == "1" ]]; then
  CALLBACK_MODE="instance receiver"
else
  CALLBACK_MODE="static"
fi

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi
if ! command -v "$ORIGINAL_CRYSTAL" >/dev/null 2>&1; then
  echo "ERROR: original Crystal compiler not found: $ORIGINAL_CRYSTAL" >&2
  exit 2
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/untyped_callback_shape_identity.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$WORKDIR"
  else
    rm -rf "$WORKDIR"
  fi
}
trap cleanup EXIT

SRC="$WORKDIR/repro.cr"
ORIGINAL_BIN="$WORKDIR/original.bin"
STAGE_BIN="$WORKDIR/stage.bin"
ORIGINAL_BUILD_LOG="$WORKDIR/original.build.log"
ORIGINAL_RUN_LOG="$WORKDIR/original.run.log"
STAGE_COMPILE_LOG="$WORKDIR/stage.compile.log"
STAGE_RUN_LOG="$WORKDIR/stage.run.log"

cat >"$SRC" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

# The explicit union return keeps the producer genuinely union-shaped at the
# dispatch boundary. Passing numeric literals here would permit a concrete
# specialization and make this probe a false green.
def produce(flag : Bool) : Int32 | Int64
  flag ? 7 : 4294967296_i64
end
CR

if [[ "$CALLBACK_RECEIVER" == "1" ]]; then
  cat >>"$SRC" <<'CR'
# Instance receiver mode models the receiver-dispatch path used by
# Tuple#reduce-style methods.
class Dispatcher
  # Deliberately untyped &block: the raw callback contract must be recovered
  # per callsite from the block body, not inherited from the first call.
  def dispatch(value : Int32 | Int64, &block)
    yield value
  end

  def dispatch_reverse(value : Int32 | Int64, &block)
    yield value
  end
end

dispatcher = Dispatcher.new
CR
  DISPATCH_PREFIX="dispatcher."
elif [[ "$CALLBACK_MODULE" == "1" ]]; then
  cat >>"$SRC" <<'CR'
module CallbackModule
  def self.dispatch(value : Int32 | Int64, &block)
    yield value
  end

  def self.dispatch_reverse(value : Int32 | Int64, &block)
    yield value
  end
end
CR
  DISPATCH_PREFIX="CallbackModule."
else
  cat >>"$SRC" <<'CR'
# Deliberately untyped &block: the raw callback contract must be recovered per
# callsite from the block body, not inherited from the first call.
def dispatch(value : Int32 | Int64, &block)
  yield value
end

# Keep a separate identical callee so its first materialized callback contract
# is the Int64 shape below; reusing dispatch would make both orders see the
# Int32 contract first during one compiler run.
def dispatch_reverse(value : Int32 | Int64, &block)
  yield value
end

CR
  DISPATCH_PREFIX=""
fi

cat >>"$SRC" <<CR
# Discovery order A: Int32-return callback, then Int64-return callback.
a32 = ${DISPATCH_PREFIX}dispatch(produce(true)) do |value|
  if value.is_a?(Int32)
    value + 1
  else
    99
  end
end
a64 = ${DISPATCH_PREFIX}dispatch(produce(false)) do |value|
  if value.is_a?(Int64)
    value + 1_i64
  else
    99_i64
  end
end

# Discovery order B: an identical callee sees the Int64 callback first.
b64 = ${DISPATCH_PREFIX}dispatch_reverse(produce(false)) do |value|
  if value.is_a?(Int64)
    value + 1_i64
  else
    99_i64
  end
end
b32 = ${DISPATCH_PREFIX}dispatch_reverse(produce(true)) do |value|
  if value.is_a?(Int32)
    value + 1
  else
    99
  end
end

# Run all four callbacks before reporting a mismatch so either discovery order
# is exercised even when the current compiler still has the known bug. The
# bitmask keeps the failing case observable in the process exit status.
status = 0
status += 1 if a32 != 8
status += 2 if a64 != 4294967297_i64
status += 4 if b64 != 4294967297_i64
status += 8 if b32 != 8
LibC.exit(status)
CR

original_build_rc=0
CRYSTAL_CACHE_DIR="$WORKDIR/original-cache" "$RUN_SAFE" "$ORIGINAL_CRYSTAL" \
  "$COMPILE_TIMEOUT_SECS" "$COMPILE_MAX_MEM_MB" build \
  "$SRC" -o "$ORIGINAL_BIN" >"$ORIGINAL_BUILD_LOG" 2>&1 || original_build_rc=$?
if [[ "$original_build_rc" -ne 0 ]]; then
  echo "FAIL: original Crystal could not build the callback-shape oracle" >&2
  tail -40 "$ORIGINAL_BUILD_LOG" >&2
  exit 1
fi

original_rc=0
"$RUN_SAFE" "$ORIGINAL_BIN" "$TIMEOUT_SECS" "$MAX_MEM_MB" >"$ORIGINAL_RUN_LOG" 2>&1 || original_rc=$?
if [[ "$original_rc" -ne 0 ]]; then
  echo "FAIL: original Crystal oracle returned $original_rc" >&2
  cat "$ORIGINAL_RUN_LOG" >&2
  exit 1
fi

stage_compile_rc=0
ADAMAS_DISABLE_INLINE_YIELD=1 "$RUN_SAFE" "$COMPILER" \
  "$COMPILE_TIMEOUT_SECS" "$COMPILE_MAX_MEM_MB" \
  "$SRC" --no-prelude -o "$STAGE_BIN" >"$STAGE_COMPILE_LOG" 2>&1 || stage_compile_rc=$?
if [[ "$stage_compile_rc" -ne 0 ]]; then
  echo "untyped callback shape identity ($CALLBACK_MODE): Adamas compile failed (exit $stage_compile_rc)" >&2
  tail -40 "$STAGE_COMPILE_LOG" >&2
  if [[ "$EXPECT_MISMATCH" == "1" ]]; then
    echo "MEASURED_RED: mode=$CALLBACK_MODE original exit 0, Adamas compile exit $stage_compile_rc"
    exit 0
  fi
  exit 1
fi

stage_rc=0
ADAMAS_DISABLE_INLINE_YIELD=1 "$RUN_SAFE" "$STAGE_BIN" \
  "$TIMEOUT_SECS" "$MAX_MEM_MB" >"$STAGE_RUN_LOG" 2>&1 || stage_rc=$?
if [[ "$stage_rc" -eq 0 ]]; then
  if [[ "$EXPECT_MISMATCH" == "1" ]]; then
    echo "FAIL: expected the current Adamas callback-shape mismatch in $CALLBACK_MODE mode, but all four cases passed" >&2
    exit 1
  fi
  echo "PASS: untyped callback shape identity preserves both return shapes and discovery orders ($CALLBACK_MODE)"
  exit 0
fi

echo "untyped callback shape identity mismatch ($CALLBACK_MODE): Adamas exit $stage_rc (original exit 0)" >&2
cat "$STAGE_RUN_LOG" >&2
if [[ "$EXPECT_MISMATCH" == "1" ]]; then
  echo "MEASURED_RED: mode=$CALLBACK_MODE original exit 0, Adamas exit $stage_rc"
  exit 0
fi
exit 1
