#!/usr/bin/env bash
# Regression test for the Pointer(T).new(integer_address).value miscompilation.
#
# Before fix: `Pointer(T).new(addr)` dropped the element type T, so the inttoptr
# result was typed as a bare/UInt8 Pointer. emit_load (llvm_backend.cr) then
# misclassified the value as a packed scalar stuffed into a ptr-width slot and
# lowered `.value` to `ptrtoint ptr to <elem>` (i.e. address & 0xFF) instead of a
# real `load`. So reading back a value stored at that address returned the low
# byte of the *address*, not the stored value.
#
# Manifested on three independent lowering paths:
#   - call-site path (lower_pointer_new_intrinsic, no owner)
#   - with-prelude path (result type resolved to the method's Class type, not
#     Pointer(T) — the .new$UInt64 suffix defeated naive rchop(".new") parsing)
#   - no-prelude intrinsic path (lower_primitive_pointer_new_intrinsic)
#
# Fix: thread the owner name into lower_pointer_new_intrinsic and derive the
# result element type via method_owner(owner) -> Pointer(T); mirror the same
# owner-derived typing in lower_primitive_pointer_new_intrinsic. The result is a
# properly-typed Pointer(T), so emit_load emits a real load.
#
# `to_unsafe`/`malloc`/`.as(T*)` pointers were never affected (they carry a
# concrete element type); only Pointer(T).new(integer) was broken.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ptr_new_value.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
COMPILE_OUT="$TMP_DIR/compile.out"
COMPILE_ERR="$TMP_DIR/compile.err"
RUN_OUT="$TMP_DIR/run.out"

cleanup() {
  if [[ "$KEEP_TMP" != "1" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

cat >"$SRC" <<'CR'
# Store a value, take its address, rebuild the pointer via Pointer(T).new(addr),
# and read it back. The read-back must load from memory, not truncate the address.
buf = Pointer(Int32).malloc(2)
buf.value = 777
p = Pointer(Int32).new(buf.address)
i32 = p.value

lbuf = Pointer(Int64).malloc(1)
lbuf.value = 1234567890123_i64
lp = Pointer(Int64).new(lbuf.address)
i64 = lp.value

s = Pointer(UInt8).malloc(4)
s.value = 65_u8
sp = Pointer(UInt8).new(s.address)
u8 = sp.value

STDERR.puts "i32=#{i32} i64=#{i64} u8=#{u8}"
STDERR.flush
CR

set +e
"$COMPILER" "$SRC" -o "$BIN" >"$COMPILE_OUT" 2>"$COMPILE_ERR"
compile_status=$?
set -e

if [[ $compile_status -ne 0 ]]; then
  echo "compile failed"
  echo "compiler: $COMPILER"
  echo "status: $compile_status"
  echo "tmp_dir: $TMP_DIR"
  echo "--- stderr ---"
  cat "$COMPILE_ERR"
  echo "--- stdout ---"
  cat "$COMPILE_OUT"
  exit 2
fi

./scripts/run_safe.sh "$BIN" 5 256 >"$RUN_OUT"
stderr_text="$(awk '/^=== STDERR ===/{flag=1;next}/^\[EXIT/{flag=0}flag' "$RUN_OUT" | tr -d '\r' | sed '/^$/d')"

echo "compiler: $COMPILER"
echo "tmp_dir: $TMP_DIR"
echo "stderr:"
printf '%s\n' "$stderr_text"

expected="i32=777 i64=1234567890123 u8=65"

if [[ "$stderr_text" == "$expected" ]]; then
  echo "fixed: Pointer(T).new(addr).value loads from memory (element type preserved)"
  exit 0
fi

echo "unexpected output (expected: $expected)"
cat "$RUN_OUT"
exit 1
