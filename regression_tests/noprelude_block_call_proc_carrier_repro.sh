#!/usr/bin/env bash
# Raw materialized-block yields and heap Proc#call use different indirect-call
# ABIs.  The block callback returns its concrete `B` type, while the HIR yield
# expression may be `Nil | B`; heap Proc calls carry the closure environment as
# an explicit first argument.  Keep both contracts covered by one fast reducer.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d /tmp/adamas_proc_carrier_XXXXXX)"
SRC="$TMP_DIR/repro.cr"
IR_BASE="$TMP_DIR/repro_ir"
BIN="$TMP_DIR/repro.bin"
COMPILE_LOG="$TMP_DIR/compile.log"
RUN_LOG="$TMP_DIR/run.log"
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$SRC" <<'CR'
lib LibC
  fun printf(format : UInt8*, ...) : Int32
  fun abort : NoReturn
end

def apply_proc(p : Int32 -> Int32, value : Int32) : Int32
  p.call(value)
end

captured = 40
p = ->(value : Int32) { value + captured }
heap_result = apply_proc(p, 2)

def invoke(&block : Int32 -> Int32?) : Int32?
  yield 1
end

raw_result = invoke { |value| value + captured }
if heap_result == 42 && raw_result == 41
  LibC.printf("proc_carrier_abi_ok\n")
else
  LibC.abort
end
CR

# Emit LLVM through the safe runner so a malformed indirect-call shape cannot
# exhaust the host while this regression is used in bootstrap loops.
ADAMAS_DISABLE_INLINE_YIELD=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 4096 \
    "$SRC" --no-prelude --emit llvm-ir --no-link -o "$IR_BASE" >"$COMPILE_LOG" 2>&1

IR="$IR_BASE.ll"
if [[ ! -s "$IR" ]]; then
  echo "proc carrier regression: missing LLVM IR" >&2
  cat "$COMPILE_LOG" >&2
  exit 1
fi

# Heap Proc#call must retain the closure environment in the generated callback
# signature and call site.
if ! grep -Eq 'define i32 @__crystal_proc_[0-9]+\(ptr %__closure_env, i32 %value\)' "$IR"; then
  echo "proc carrier regression: heap callback lost its closure-env parameter" >&2
  exit 1
fi
if ! grep -Eq 'call i32 %r[0-9]+\(ptr %r[0-9]+, i32 %value\)' "$IR"; then
  echo "proc carrier regression: heap Proc#call did not pass the closure env" >&2
  exit 1
fi

# The raw callback has a concrete i32 ABI even though invoke returns Nil|Int32;
# the result is wrapped after the indirect call.
if ! grep -Eq 'define %Nil\$_\$OR\$_Int32\.union @invoke\$\$block\(' "$IR"; then
  echo "proc carrier regression: nullable invoke return shape disappeared" >&2
  exit 1
fi
if ! grep -Eq 'call i32 %r[0-9]+\(i32 1\)' "$IR"; then
  echo "proc carrier regression: raw callback does not use its concrete i32 ABI" >&2
  exit 1
fi
if grep -Eq 'call %Nil\$_\$OR\$_Int32\.union %r[0-9]+\(i32 1\)' "$IR"; then
  echo "proc carrier regression: raw callback still uses the nullable union ABI" >&2
  exit 1
fi

ADAMAS_DISABLE_INLINE_YIELD=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 4096 \
    "$SRC" --no-prelude -o "$BIN" >"$COMPILE_LOG" 2>&1
"$ROOT_DIR/scripts/run_safe.sh" "$BIN" 5 512 >"$RUN_LOG" 2>&1

stdout="$(awk '/^=== STDOUT ===/{flag=1;next}/^=== STDERR ===/{flag=0}flag' "$RUN_LOG" | tr -d '\r')"
if [[ "$stdout" != "proc_carrier_abi_ok" ]]; then
  echo "proc carrier regression: unexpected output" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

echo "noprelude_block_call_proc_carrier_ok"
