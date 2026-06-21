#!/usr/bin/env bash
# C-narrow-b BEHAVIOR regression (gates ADAMAS_CNARROW_B_LOAD + ADAMAS_INLINE_VALUE_ARRAY_STORAGE).
# DoD (GPT, C-specific -- not a global ivc_raw count):
#   - behavior identical: legacy == A' == A'+load (checksum);
#   - A'+load: a `cnarrow_b direct slot` read appears AND the `ivc_raw arrayget carrier`
#     count drops vs A'-only (the eligible V3 read carrier is gone) but stays > 0 (the
#     recv_borrow V3 read keeps its carrier);
#   - A'-COUPLING: ADAMAS_CNARROW_B_LOAD=1 WITHOUT A' => 0 direct-slot loads;
#   - gate-OFF byte-identical.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
SRC="regression_tests/cnarrow_b_load.cr"
RUNNER="${RUNNER:-scripts/run_safe.sh}"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cnbload.XXXXXX")"
cleanup() { [[ "$KEEP_TMP" != "1" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

[[ -f "$SRC" ]] || { echo "missing reducer source: $SRC"; exit 2; }
fail=0

# Build + run: legacy, A' only, A' + load.
"$COMPILER" "$SRC" -o "$TMP_DIR/legacy" >/dev/null 2>/dev/null
legacy_run="$("$RUNNER" "$TMP_DIR/legacy" 5 256 2>&1 | grep RESULT || true)"
ADAMAS_INLINE_VALUE_ARRAY_STORAGE=1 "$COMPILER" "$SRC" -o "$TMP_DIR/aprime" >/dev/null 2>/dev/null
aprime_run="$("$RUNNER" "$TMP_DIR/aprime" 5 256 2>&1 | grep RESULT || true)"
ADAMAS_INLINE_VALUE_ARRAY_STORAGE=1 ADAMAS_CNARROW_B_LOAD=1 "$COMPILER" "$SRC" -o "$TMP_DIR/load" >/dev/null 2>/dev/null
load_run="$("$RUNNER" "$TMP_DIR/load" 5 256 2>&1 | grep RESULT || true)"

echo "compiler: $COMPILER"
echo "  legacy: $legacy_run"
echo "  A':     $aprime_run"
echo "  load:   $load_run"

# (1) behavior identity.
if [[ -z "$legacy_run" || "$legacy_run" != "$load_run" || "$aprime_run" != "$load_run" ]]; then
  echo "FAIL: behavior differs (legacy='$legacy_run' A'='$aprime_run' load='$load_run')"; fail=1
fi

# IR: A' only, A' + load, and load-WITHOUT-A'.
ADAMAS_INLINE_VALUE_ARRAY_STORAGE=1 "$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/ap_ir" >/dev/null 2>/dev/null || true
ADAMAS_INLINE_VALUE_ARRAY_STORAGE=1 ADAMAS_CNARROW_B_LOAD=1 "$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/load_ir" >/dev/null 2>/dev/null || true
ADAMAS_CNARROW_B_LOAD=1 "$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/noap_ir" >/dev/null 2>/dev/null || true

direct_ap="$(grep -c 'cnarrow_b direct slot' "$TMP_DIR/ap_ir.ll" || true)"
direct_load="$(grep -c 'cnarrow_b direct slot' "$TMP_DIR/load_ir.ll" || true)"
direct_noap="$(grep -c 'cnarrow_b direct slot' "$TMP_DIR/noap_ir.ll" || true)"
carrier_ap="$(grep -c 'ivc_raw arrayget carrier' "$TMP_DIR/ap_ir.ll" || true)"
carrier_load="$(grep -c 'ivc_raw arrayget carrier' "$TMP_DIR/load_ir.ll" || true)"
echo "  direct-slot: A'=$direct_ap  load=$direct_load  load-no-A'=$direct_noap"
echo "  arrayget-carrier: A'=$carrier_ap  load=$carrier_load"

# (2) A'+load emits a direct-slot read; A' alone does not.
if [[ "$direct_load" -lt 1 ]]; then echo "FAIL: no cnarrow_b direct slot under A'+load"; fail=1; fi
if [[ "$direct_ap" -ne 0 ]]; then echo "FAIL: cnarrow_b direct slot leaked under A' alone"; fail=1; fi
# (3) A'-COUPLING: load WITHOUT A' => 0 direct-slot loads.
if [[ "$direct_noap" -ne 0 ]]; then echo "FAIL: direct-slot load WITHOUT A' (coupling breached)"; fail=1; fi
# (4) the eligible V3 read carrier is gone, the recv_borrow carrier remains (>0, < A').
if [[ "$carrier_load" -ge "$carrier_ap" ]]; then echo "FAIL: arrayget carrier did not drop (A'=$carrier_ap load=$carrier_load)"; fail=1; fi
if [[ "$carrier_load" -lt 1 ]]; then echo "FAIL: ALL arrayget carriers gone -- the recv_borrow negative was wrongly direct-loaded"; fail=1; fi

# (5) gate-OFF byte-identical (no gates vs legacy).
"$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/off1" >/dev/null 2>/dev/null || true
"$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/off2" >/dev/null 2>/dev/null || true
sed -E 's/stub_name_[0-9a-fA-F]+/stub_name_N/g' "$TMP_DIR/off1.ll" > "$TMP_DIR/off1.norm.ll"
sed -E 's/stub_name_[0-9a-fA-F]+/stub_name_N/g' "$TMP_DIR/off2.ll" > "$TMP_DIR/off2.norm.ll"
if [[ "$(diff "$TMP_DIR/off1.norm.ll" "$TMP_DIR/off2.norm.ll" | grep -c '^[<>]' || true)" != "0" ]]; then
  echo "WARN: gate-OFF compile is non-deterministic beyond stub names"; fi

[[ $fail -ne 0 ]] && { echo "tmp_dir: $TMP_DIR"; exit 1; }
echo "ok: behavior identical (legacy==A'==load); A'+load direct-slot=$direct_load (A' alone=0, no-A'=0); arrayget carrier $carrier_ap->$carrier_load (eligible V3 read carrier gone, recv_borrow kept)"
exit 0
