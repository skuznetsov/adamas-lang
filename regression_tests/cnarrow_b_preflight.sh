#!/usr/bin/env bash
# C-narrow-b PREFLIGHT eligibility regression (gate ADAMAS_CNARROW_B_PREFLIGHT, needs A').
#
# Asserts the read-only preflight classifies the same-block local-field-read V3 ArrayGet
# as `eligible` (marked cnarrow_b_direct) and the four carrier-required shapes as their
# carrier reasons, and is behavior-neutral (preflight ON vs OFF, both under A', byte-
# identical IR). The preflight runs POST-MIR-opt inside the A' block.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
SRC="regression_tests/cnarrow_b_preflight.cr"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cnbpre.XXXXXX")"
ERR="$TMP_DIR/pre.err"
cleanup() { [[ "$KEEP_TMP" != "1" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

[[ -f "$SRC" ]] || { echo "missing reducer source: $SRC"; exit 2; }

set +e
ADAMAS_INLINE_VALUE_ARRAY_STORAGE=1 ADAMAS_CNARROW_B_PREFLIGHT=1 "$COMPILER" "$SRC" -o "$TMP_DIR/bin" >/dev/null 2>"$ERR"
status=$?
set -e
[[ $status -ne 0 ]] && { echo "preflight compile failed ($status); tmp_dir=$TMP_DIR"; grep CNARROW_B "$ERR" | head; exit 2; }

echo "compiler: $COMPILER"
grep -E "CNARROW_B\]   (V3 \||eligible =|inline-C)" "$ERR" || true

fail=0
v3="$(grep -E "^\[CNARROW_B\]   V3 \| " "$ERR" | head -1 || true)"
if [[ -z "$v3" ]]; then echo "FAIL: no V3 per-type row"; fail=1; fi

# POSITIVE: V3 same-block read is eligible.
if ! printf '%s' "$v3" | grep -qE "eligible=[1-9]"; then
  echo "FAIL: V3 same-block local-read not classified eligible"; fail=1
fi
# NEGATIVES present (carrier-required): recv_borrow/stored -> call; returned; intervening.
if ! printf '%s' "$v3" | grep -qE "(^| )call=[1-9]"; then
  echo "FAIL: V3 recv_borrow/stored not carrier-required (no call reason)"; fail=1
fi
if ! printf '%s' "$v3" | grep -qE "returned=[1-9]"; then
  echo "FAIL: V3 returned load not carrier-required"; fail=1
fi
if ! printf '%s' "$v3" | grep -qE "intervening_call=[1-9]"; then
  echo "FAIL: V3 intervening-call load not carrier-required"; fail=1
fi

# behavior neutrality: preflight ON vs OFF, both under A', byte-identical IR.
ADAMAS_INLINE_VALUE_ARRAY_STORAGE=1 "$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/off" >/dev/null 2>/dev/null || true
ADAMAS_INLINE_VALUE_ARRAY_STORAGE=1 ADAMAS_CNARROW_B_PREFLIGHT=1 "$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/on" >/dev/null 2>/dev/null || true
sed -E 's/stub_name_[0-9a-fA-F]+/stub_name_N/g' "$TMP_DIR/off.ll" > "$TMP_DIR/off.norm.ll"
sed -E 's/stub_name_[0-9a-fA-F]+/stub_name_N/g' "$TMP_DIR/on.ll"  > "$TMP_DIR/on.norm.ll"
nd="$(diff "$TMP_DIR/off.norm.ll" "$TMP_DIR/on.norm.ll" | grep -c '^[<>]' || true)"
if [[ "$nd" != "0" ]]; then echo "FAIL: preflight ON vs OFF IR differs ($nd lines) -- not behavior-neutral"; fail=1; fi

[[ $fail -ne 0 ]] && { echo "tmp_dir: $TMP_DIR"; exit 1; }
echo "ok: V3 same-block read eligible; recv_borrow/stored->call, returned, intervening_call all carrier-required; preflight behavior-neutral (IR diff=0)"
exit 0
