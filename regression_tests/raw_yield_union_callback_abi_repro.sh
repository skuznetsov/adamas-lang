#!/usr/bin/env bash
# No-prelude runtime regression for raw yield callbacks whose formal argument
# is a full union. The callback must receive the union tag and payload together.
# UNTYPED_CALLBACK=1 exercises the still-open untyped-carrier frontier and
# asserts the same correct result; it currently fails with runtime exit 81.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/raw_yield_union_callback_abi.XXXXXX")"

cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

SRC="$TMP_DIR/union_yield.cr"
BIN="$TMP_DIR/union_yield"

cat >"$SRC" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def dispatch(value : Int32 | Int64, &block : (Int32 | Int64) -> Int32)
  yield value
end

small = dispatch(7) do |value|
  if value.is_a?(Int32)
    value + 1
  else
    99
  end
end

large = dispatch(4294967296_i64) do |value|
  if value.is_a?(Int64)
    (value >> 32).to_i
  else
    99
  end
end

LibC.exit(81) unless small == 8
LibC.exit(82) unless large == 1
LibC.exit(0)
CR

# Preserve the numeric union at the caller boundary: passing plain literals
# permits concrete specialization and would be a false green for this probe.
if [[ "${UNTYPED_CALLBACK:-0}" == "1" ]]; then
  cat >"$SRC" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def produce(flag : Bool) : Int32 | Int64
  flag ? 7 : 4294967296_i64
end

def dispatch(value : Int32 | Int64, &block)
  yield value
end

small = dispatch(produce(true)) do |value|
  if value.is_a?(Int32)
    value + 1
  else
    99
  end
end
large = dispatch(produce(false)) do |value|
  if value.is_a?(Int64)
    (value >> 32).to_i
  else
    99
  end
end
LibC.exit(81) unless small == 8
LibC.exit(82) unless large == 1
LibC.exit(0)
CR
fi

COMPILE_LOG="$TMP_DIR/compile.log"
if ! ADAMAS_DISABLE_INLINE_YIELD=1 "$RUN_SAFE" "$COMPILER" 120 8192 \
  "$SRC" --no-prelude -o "$BIN" >"$COMPILE_LOG" 2>&1; then
  echo "FAIL: raw yield union callback regression did not compile" >&2
  tail -40 "$COMPILE_LOG" >&2
  exit 1
fi

RUN_LOG="$TMP_DIR/run.log"
if ! ADAMAS_DISABLE_INLINE_YIELD=1 "$RUN_SAFE" "$BIN" 5 512 >"$RUN_LOG" 2>&1; then
  echo "FAIL: raw yield callback received an invalid union ABI" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

PROC_SRC="$TMP_DIR/mixed_union_yield_proc.cr"
PROC_BIN="$TMP_DIR/mixed_union_yield_proc"

cat >"$PROC_SRC" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def dispatch(value : Int32 | Int64, extra : Int32, &block : Proc(Int32 | Int64, Int32, Int32))
  yield value, extra
end

small = dispatch(7, 4) do |value, extra|
  if value.is_a?(Int32)
    value + extra
  else
    99
  end
end

large = dispatch(4294967296_i64, 4) do |value, extra|
  if value.is_a?(Int64)
    (value >> 32).to_i + extra
  else
    99
  end
end

LibC.exit(81) unless small == 11
LibC.exit(82) unless large == 5
LibC.exit(0)
CR

PROC_COMPILE_LOG="$TMP_DIR/mixed_union_yield_proc.compile.log"
if ! ADAMAS_DISABLE_INLINE_YIELD=1 "$RUN_SAFE" "$COMPILER" 120 8192 \
  "$PROC_SRC" --no-prelude -o "$PROC_BIN" >"$PROC_COMPILE_LOG" 2>&1; then
  echo "FAIL: explicit Proc mixed callback regression did not compile" >&2
  tail -40 "$PROC_COMPILE_LOG" >&2
  exit 1
fi

PROC_RUN_LOG="$TMP_DIR/mixed_union_yield_proc.run.log"
if ! ADAMAS_DISABLE_INLINE_YIELD=1 "$RUN_SAFE" "$PROC_BIN" 5 512 >"$PROC_RUN_LOG" 2>&1; then
  echo "FAIL: explicit Proc mixed callback received an invalid union ABI" >&2
  cat "$PROC_RUN_LOG" >&2
  exit 1
fi

echo "PASS: raw yield callback preserves full union ABI"
echo "PASS: explicit Proc mixed callback preserves full union ABI"
