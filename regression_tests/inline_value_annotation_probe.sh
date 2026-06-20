#!/usr/bin/env bash
# Diagnostic regression for the A' DURABLE annotation step (infrastructure-only).
#
# Gate ADAMAS_INLINE_VALUE_ANNOTATE runs populate_inline_value_safe_set (the SAME
# { bv && !vd && !erased_flow } analysis as the safe-set probe, with provenance
# marking ON) and persists:
#   - Type#inline_value_safe                 (per-type "inline-store eligible" flag)
#   - GetElementPtrDynamic#array_buffer_value (per-site Array(C) @buffer value access)
# then verify_inline_value_annotation reads the PERSISTED marks back in a separate
# pass and prints [IVANNOT] lines.
#
# This commit is "same computation, durable annotation, NO behavior": NO lowering
# site reads either mark. Asserts:
#   (1) Vec2 is SAFE-MARKED (Type#inline_value_safe = true).
#   (2) Vraw is NOT marked (value_derived access → not inline-store eligible). This
#       doubles as the future behavior reducer's "unsafe types are not eligible".
#   (3) array_buffer_value gep marks land ONLY inside Array(...) bodies — outside
#       MUST be 0 (the raw Pointer(Vraw) path is NOT marked as an Array buffer).
#   (4) NO behavior: the emitted LLVM IR carries no `ivc_raw` (no codegen consumes
#       the marks), and gate ON vs OFF IR is byte-identical (normalized for the
#       pre-existing non-deterministic @.stub_name_<hash> symbols).
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
SRC="regression_tests/inline_value_safe_set_probe.cr"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ivannot.XXXXXX")"
ANN_ERR="$TMP_DIR/ann.err"
LL_OFF="$TMP_DIR/off.norm.ll"
LL_ON="$TMP_DIR/on.norm.ll"

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

set +e
ADAMAS_INLINE_VALUE_ANNOTATE=1 "$COMPILER" "$SRC" -o "$TMP_DIR/bin" >/dev/null 2>"$ANN_ERR"
status=$?
set -e
if [[ $status -ne 0 ]]; then
  echo "annotate compile failed (status $status); tmp_dir=$TMP_DIR"
  grep "IVANNOT" "$ANN_ERR" || true
  exit 2
fi

echo "compiler: $COMPILER"
grep -E "IVANNOT\] (inline_value_safe types|  SAFE-MARKED Vec2|  not-marked Vraw|array_buffer_value)" "$ANN_ERR" || true

fail=0

# (1) Vec2 SAFE-MARKED.
if ! grep -qE "^\[IVANNOT\]   SAFE-MARKED Vec2$" "$ANN_ERR"; then
  echo "FAIL: Vec2 not SAFE-MARKED (Type#inline_value_safe)"
  fail=1
fi

# (2) Vraw NOT marked.
if ! grep -qE "^\[IVANNOT\]   not-marked Vraw$" "$ANN_ERR"; then
  echo "FAIL: Vraw should be not-marked (value_derived access)"
  fail=1
fi
if grep -qE "^\[IVANNOT\]   SAFE-MARKED Vraw$" "$ANN_ERR"; then
  echo "FAIL: Vraw is SAFE-MARKED but must be excluded"
  fail=1
fi

# (3) array_buffer_value marks inside Array bodies only (outside == 0, inside >= 1).
marks_line="$(grep -E "array_buffer_value gep marks:" "$ANN_ERR" || true)"
inside="$(printf '%s' "$marks_line" | grep -oE "inside Array\(\.\.\.\) bodies=[0-9]+" | grep -oE "[0-9]+$" || echo "")"
outside="$(printf '%s' "$marks_line" | grep -oE "outside=[0-9]+" | grep -oE "[0-9]+$" || echo "")"
if [[ -z "$inside" || "$inside" -lt 1 ]]; then
  echo "FAIL: expected >=1 array_buffer_value mark inside an Array(...) body (got '${inside:-none}')"
  fail=1
fi
if [[ "${outside:-x}" != "0" ]]; then
  echo "FAIL: array_buffer_value marks outside an Array body = '${outside:-none}' (MUST be 0)"
  fail=1
fi

# (4a) NO behavior: emitted IR carries no ivc_raw (no codegen reads the marks).
ADAMAS_INLINE_VALUE_ANNOTATE=1 "$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/on" >/dev/null 2>/dev/null || true
"$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/off" >/dev/null 2>/dev/null || true
if grep -q "ivc_raw" "$TMP_DIR/on.ll"; then
  echo "FAIL: ivc_raw present in annotated IR — a codegen path is reading the marks (behavior leaked)"
  fail=1
fi

# (4b) gate ON vs OFF IR byte-identical modulo stub-name hashes.
sed -E 's/stub_name_[0-9]+/stub_name_N/g' "$TMP_DIR/off.ll" > "$LL_OFF"
sed -E 's/stub_name_[0-9]+/stub_name_N/g' "$TMP_DIR/on.ll"  > "$LL_ON"
norm_diff="$(diff "$LL_OFF" "$LL_ON" | grep -c '^[<>]' || true)"
if [[ "$norm_diff" != "0" ]]; then
  echo "FAIL: annotate ON vs OFF IR differs ($norm_diff normalized lines) — annotation is not behavior-neutral"
  fail=1
fi

if [[ $fail -ne 0 ]]; then
  echo "tmp_dir: $TMP_DIR"
  exit 1
fi

echo "ok: Vec2 SAFE-MARKED, Vraw not-marked; array_buffer_value marks inside Array only (inside=$inside outside=0);"
echo "    no ivc_raw in IR; annotate gate-neutral (normalized IR diff=0) — durable annotation, no behavior"
exit 0
