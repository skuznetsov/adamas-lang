#!/usr/bin/env bash
# A' BEHAVIOR: main-inlined Array(C) eligibility (closes the v1 bv-limit).
# MW is used via push + main-inlined arr[i] / arr[i]=v (ArrayGet/ArraySet, no
# Array(MW)#unsafe_fetch body). Asserts MW is now ELIGIBLE and the inline ABI flips
# correctly (behavior-identical to legacy), proving eligibility is no longer
# dependent on call-shaped Array usage.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
SRC="regression_tests/inline_value_array_main_inlined_probe.cr"
RUNNER="${RUNNER:-scripts/run_safe.sh}"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ivmain.XXXXXX")"
cleanup() { [[ "$KEEP_TMP" != "1" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

if [[ ! -f "$SRC" ]]; then echo "missing reducer source: $SRC"; exit 2; fi
fail=0

"$COMPILER" "$SRC" -o "$TMP_DIR/off" >/dev/null 2>/dev/null
off_run="$("$RUNNER" "$TMP_DIR/off" 5 256 2>&1 | grep RESULT || true)"
ADAMAS_INLINE_VALUE_ARRAY_STORAGE=1 ADAMAS_IVC_VERIFY=1 "$COMPILER" "$SRC" -o "$TMP_DIR/on" 2>"$TMP_DIR/facts" >/dev/null
on_run="$("$RUNNER" "$TMP_DIR/on" 5 256 2>&1 | grep RESULT || true)"

echo "compiler: $COMPILER"
echo "  OFF: $off_run"
echo "  ON:  $on_run"
grep -E "ABIFACTS\]   (ELIGIBLE|ineligible) MW " "$TMP_DIR/facts" || true

# (1) MW eligible (main-inlined usage now establishes bv).
if ! grep -qE "^\[ABIFACTS\]   ELIGIBLE MW " "$TMP_DIR/facts"; then
  echo "FAIL: MW not ELIGIBLE — main-inlined ArrayGet/ArraySet bv not established"; fail=1
fi
# (2) behavior-identical and correct.
if [[ -z "$off_run" || -z "$on_run" || "$off_run" != "$on_run" ]]; then
  echo "FAIL: gate ON vs OFF behavior differs (or missing RESULT)"; fail=1
fi
# (3) ivc_raw fires inside an Array(MW)# function (actually inline-stored).
ADAMAS_INLINE_VALUE_ARRAY_STORAGE=1 "$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/ir" >/dev/null 2>/dev/null || true
mw_ivc="$(awk '/^define/{inv=($0 ~ /Array.LMW.R.H/)} inv&&/ivc_raw/{c++} END{print c+0}' "$TMP_DIR/ir.ll")"
if [[ "$mw_ivc" -lt 1 ]]; then
  echo "FAIL: no ivc_raw inside Array(MW)# functions (MW not actually inline-stored)"; fail=1
fi
# (4) gate OFF clean.
"$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/off_ir" >/dev/null 2>/dev/null || true
if [[ "$(grep -c ivc_raw "$TMP_DIR/off_ir.ll" || true)" != "0" ]]; then
  echo "FAIL: gate-OFF IR has ivc_raw"; fail=1
fi

if [[ $fail -ne 0 ]]; then echo "tmp_dir: $TMP_DIR"; exit 1; fi
echo "ok: main-inlined MW ELIGIBLE + inline-stored (ivc_raw in Array(MW)#=$mw_ivc); behavior-identical; gate-OFF clean"
exit 0
