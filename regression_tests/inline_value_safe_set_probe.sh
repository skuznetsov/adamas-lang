#!/usr/bin/env bash
# Diagnostic regression for the A' step-(c) inline-value SAFE-SET probe.
#
# The read-only probe (gate ADAMAS_INLINE_VALUE_SAFE_SET_PROBE) classifies each
# InlineValueCopy candidate element type C by the v1 rule { C | bv && !vd && !erased_flow }:
#   bv          — a buffer_value (@buffer-base chain) Load/Store of C exists.
#   vd          — a value_derived access of C exists: a Load OR Store through a raw
#                 Pointer(C) that is not the @buffer chain → HAZARD.
#   erased_flow — Array(C) (or an upcast Indexable/Enumerable(C)) flows into a
#                 type-erased body → HAZARD (the SOUND erased gate).
#   mega_union  — INFORMATIONAL: C is in some shared Indexable(T)#fetch return union;
#                 over-fires, so it is NOT used as a gate.
#
# Asserts, in a single compile of the reducer:
#   (1) Vec2  => SAFE   (bv=1 vd=0 erased_flow=0): Array(Vec2) access only, INCLUDING
#       the erasure-attempt forms (Indexable(Vec2) param, .as cast, two-implementer
#       abstract dispatch) — all monomorphize to the concrete Array(Vec2)# body.
#   (2) Vraw  => UNSAFE via value_derived access (bv=1 vd=1): raw Pointer(Vraw).
#   (3) flow-based erased=0 globally (this compiler monomorphizes container access,
#       so no candidate array is ever type-erased — erased_flow is a sound but
#       dormant guard here; the reducer exercises the abstract-dispatch forms to
#       make this a durable test, not a one-shot observation).
#   (4) The over-coarse variant mega-union signal WOULD wrongly exclude >=1 type
#       that the flow-based gate correctly keeps (proves flow-based is the right gate).
#   (5) GATE NEUTRALITY: probe ON vs OFF LLVM IR byte-identical once the pre-existing
#       non-deterministic @.stub_name_<hash> symbols are normalized (read-only probe).
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
SRC="regression_tests/inline_value_safe_set_probe.cr"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ivsafeset.XXXXXX")"
PROBE_ERR="$TMP_DIR/probe.err"
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
ADAMAS_INLINE_VALUE_SAFE_SET_PROBE=1 "$COMPILER" "$SRC" -o "$TMP_DIR/bin" >/dev/null 2>"$PROBE_ERR"
status=$?
set -e
if [[ $status -ne 0 ]]; then
  echo "probe compile failed (status $status); tmp_dir=$TMP_DIR"
  grep "SAFESET" "$PROBE_ERR" || true
  exit 2
fi

echo "compiler: $COMPILER"
grep -E "SAFESET\] (InlineValueCopy candidates=|\(flow-based|  Vec2  |  Vraw  )" "$PROBE_ERR" || true

fail=0

# (1) Vec2 SAFE: bv=1 vd=0 erased_flow=0, listed WITHOUT an "— <reason>" suffix.
if ! grep -qE "^\[SAFESET\]   Vec2  \(bv=1 vd=0 erased_flow=0 mega_union=[01]\)$" "$PROBE_ERR"; then
  echo "FAIL: Vec2 not in SAFE-SET as (bv=1 vd=0 erased_flow=0)"
  fail=1
fi

# (2) Vraw UNSAFE via value_derived access.
if ! grep -qE "^\[SAFESET\]   Vraw  \(bv=1 vd=1 erased_flow=0 mega_union=[01]\) — value_derived access$" "$PROBE_ERR"; then
  echo "FAIL: Vraw not excluded as value_derived access (bv=1 vd=1)"
  fail=1
fi

# (3) flow-based erased=0 globally.
if ! grep -qE "flow-based erased=0;" "$PROBE_ERR"; then
  echo "FAIL: expected flow-based erased=0 globally"
  fail=1
fi

# (4) mega-union over-count: it WOULD wrongly exclude >=1 type vs the flow gate.
mu_wrong="$(grep -oE "WRONGLY exclude vs flow=[0-9]+" "$PROBE_ERR" | grep -oE "[0-9]+$" || echo "")"
if [[ -z "$mu_wrong" || "$mu_wrong" -lt 1 ]]; then
  echo "FAIL: expected variant mega-union to wrongly exclude >=1 type (got '${mu_wrong:-none}')"
  fail=1
fi

# (5) gate neutrality: ON vs OFF IR identical modulo stub-name hashes.
"$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/off" >/dev/null 2>/dev/null || true
ADAMAS_INLINE_VALUE_SAFE_SET_PROBE=1 "$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/on" >/dev/null 2>/dev/null || true
sed -E 's/stub_name_[0-9]+/stub_name_N/g' "$TMP_DIR/off.ll" > "$LL_OFF"
sed -E 's/stub_name_[0-9]+/stub_name_N/g' "$TMP_DIR/on.ll"  > "$LL_ON"
norm_diff="$(diff "$LL_OFF" "$LL_ON" | grep -c '^[<>]' || true)"
if [[ "$norm_diff" != "0" ]]; then
  echo "FAIL: probe ON vs OFF IR differs ($norm_diff normalized lines) — probe is not read-only"
  fail=1
fi

if [[ $fail -ne 0 ]]; then
  echo "tmp_dir: $TMP_DIR"
  exit 1
fi

echo "ok: Vec2 SAFE (bv,!vd,!erased_flow even under abstract dispatch); Vraw UNSAFE (value_derived access);"
echo "    flow-based erased=0; mega-union would wrongly exclude $mu_wrong type(s); probe gate-neutral (normalized IR diff=0)"
exit 0
