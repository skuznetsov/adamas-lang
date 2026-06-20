#!/usr/bin/env bash
# Diagnostic regression for the A' Array-buffer provenance marker (read-only).
#
# The A' marker identifies which raw GetElementPtrDynamic sites over an
# InlineValueCopy-candidate element actually address an Array element buffer
# (Array.@buffer) via BUFFER-BASE PROVENANCE — NOT by element type (refuted:
# over-fires on every Pointer(T)#value, incl. the IO#gets_peek `switch i32`
# blocker) and NOT by enclosing-function name alone (too fragile).
#
# The mark set is the `buffer_value` category: a candidate gep_dyn whose base is
# Load(static GEP @buffer of an Array(C) self) AND which is the address of a
# Load/Store of the element type C.
#
# This script asserts, on a probe that mixes a POSITIVE Array(Vec2) inline-buffer
# access with a NEGATIVE raw Pointer(Vec2) indexed access:
#
#   (1) THE A' HAZARD INVARIANT: 0 buffer_value marks land OUTSIDE an Array body.
#   (2) POSITIVE: Array(Vec2)#push and #unsafe_fetch ARE in buffer_value.
#   (3) NEGATIVE: the raw Pointer(Vec2) access (in __adamas_main) is NOT in
#       buffer_value (it falls in value_derived — value access, no @buffer chain).
#   (4) GATE NEUTRALITY: gate ON vs OFF LLVM IR is byte-identical once the
#       pre-existing non-deterministic @.stub_name_<hash> symbols are normalized.
#
# Strictly read-only: the probe only writes to STDERR; it never mutates MIR/IR
# and emits no ivc_raw / memcpy. (1)-(3) prove the A' marker is precise BEFORE any
# behavior change; (4) proves the diagnostic itself is free of side effects.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
SRC="regression_tests/array_buffer_provenance_marker_probe.cr"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/abufprov.XXXXXX")"
PROBE_ERR="$TMP_DIR/probe.err"
LL_OFF="$TMP_DIR/off.ll"
LL_ON="$TMP_DIR/on.ll"

cleanup() {
  if [[ "$KEEP_TMP" != "1" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

if [[ ! -f "$SRC" ]]; then
  echo "missing reducer source: $SRC"
  exit 2
fi

# --- run the probe -----------------------------------------------------------
set +e
ADAMAS_ARRAY_BUFFER_PROVENANCE_PROBE=1 "$COMPILER" "$SRC" -o "$TMP_DIR/bin" >/dev/null 2>"$PROBE_ERR"
probe_status=$?
set -e
if [[ $probe_status -ne 0 ]]; then
  echo "probe compile failed (status $probe_status); tmp_dir=$TMP_DIR"
  grep "ABUF_PROBE" "$PROBE_ERR" || true
  exit 2
fi

echo "compiler: $COMPILER"
grep "ABUF_PROBE" "$PROBE_ERR" | head -3

fail=0

# (1) hazard invariant: 0 buffer_value marks outside an Array body.
if ! grep -q "A' MARK SET (buffer_value) sites OUTSIDE an Array(...) body = 0 " "$PROBE_ERR"; then
  echo "FAIL (1): A' mark set has site(s) outside an Array body"
  grep "OUTSIDE an Array" "$PROBE_ERR" || true
  fail=1
fi

# Extract the buffer_value block (from its header to the next category header).
bv_block="$(awk '
  /\[ABUF_PROBE\] buffer_value:/{cap=1; next}
  /\[ABUF_PROBE\] (value_derived|buffer_ptr_arith|neither):/{cap=0}
  cap' "$PROBE_ERR")"

# (2) positive: Array(Vec2)#push and #unsafe_fetch are in buffer_value.
if ! grep -q "Array(Vec2)#push" <<<"$bv_block"; then
  echo "FAIL (2a): Array(Vec2)#push not in buffer_value"; fail=1
fi
if ! grep -q "Array(Vec2)#unsafe_fetch" <<<"$bv_block"; then
  echo "FAIL (2b): Array(Vec2)#unsafe_fetch not in buffer_value"; fail=1
fi

# (3) negative: the raw Pointer(Vec2) access (in __adamas_main) must NOT be in
# buffer_value. (It is value_derived: value access, no @buffer-chain provenance.)
if grep -q "__adamas_main" <<<"$bv_block"; then
  echo "FAIL (3): raw Pointer(Vec2) access (__adamas_main) leaked into buffer_value"; fail=1
fi

# (4) gate neutrality: ON vs OFF IR identical modulo stub-name hashes.
"$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/off" >/dev/null 2>/dev/null || true
ADAMAS_ARRAY_BUFFER_PROVENANCE_PROBE=1 "$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/on" >/dev/null 2>/dev/null || true
# --emit llvm-ir writes <out>.ll
sed -E 's/stub_name_[0-9]+/stub_name_N/g' "$TMP_DIR/off.ll" > "$LL_OFF"
sed -E 's/stub_name_[0-9]+/stub_name_N/g' "$TMP_DIR/on.ll"  > "$LL_ON"
norm_diff="$(diff "$LL_OFF" "$LL_ON" | grep -c '^[<>]' || true)"
if [[ "$norm_diff" != "0" ]]; then
  echo "FAIL (4): gate ON vs OFF IR differs ($norm_diff normalized lines) — probe is not read-only"
  fail=1
fi

if [[ $fail -ne 0 ]]; then
  echo "tmp_dir: $TMP_DIR"
  exit 1
fi

echo "ok: A' buffer_value marks 0 outside Array; Array(Vec2)#push/#unsafe_fetch marked; raw Pointer(Vec2) not marked; gate neutral (normalized IR diff=0)"
exit 0
