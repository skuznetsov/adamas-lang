#!/usr/bin/env bash
# A' BEHAVIOR regression: inline Array(V3) storage (gate ADAMAS_INLINE_VALUE_ARRAY_STORAGE).
#
# The first commit where LLVM consumes the A' facts and changes the Array(C) ABI:
# a leaf-POD value struct is stored INLINE in the Array buffer (stride C.size), read
# back as an escape-safe heap-carrier copy, and the whole mutation family
# (push/grow/realloc, [], delete_at/shift/insert/concat, clear) uses the inline stride.
#
# CRITICAL: this asserts the flip happens SPECIFICALLY for V3 — an earlier version
# only checked GLOBAL `ivc_raw` presence, which passed even when V3 was ineligible
# (the ivc_raw came from other eligible stdlib types). That was a value-proxy bug.
# So we now assert V3-specific facts AND inline IR AND behavior-identity.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
SRC="regression_tests/inline_value_array_storage_behavior.cr"
RUNNER="${RUNNER:-scripts/run_safe.sh}"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ivbeh.XXXXXX")"
cleanup() { [[ "$KEEP_TMP" != "1" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

if [[ ! -f "$SRC" ]]; then echo "missing reducer source: $SRC"; exit 2; fi
fail=0

# Build + run gate OFF (legacy baseline) and gate ON (inline storage).
"$COMPILER" "$SRC" -o "$TMP_DIR/off" >/dev/null 2>/dev/null
off_run="$("$RUNNER" "$TMP_DIR/off" 5 256 2>&1 | grep RESULT || true)"
ADAMAS_INLINE_VALUE_ARRAY_STORAGE=1 ADAMAS_IVC_VERIFY=1 "$COMPILER" "$SRC" -o "$TMP_DIR/on" 2>"$TMP_DIR/on.facts" >/dev/null
on_run="$("$RUNNER" "$TMP_DIR/on" 5 256 2>&1 | grep RESULT || true)"

echo "compiler: $COMPILER"
echo "  OFF: $off_run"
echo "  ON:  $on_run"
grep -E "ABIFACTS\]   (ELIGIBLE V3|stride-geps V3)" "$TMP_DIR/on.facts" || true

# (1) behavior-identical AND the correct value.
if [[ -z "$off_run" || -z "$on_run" ]]; then echo "FAIL: missing RESULT (crash?)"; fail=1; fi
if [[ "$off_run" != "$on_run" ]]; then echo "FAIL: gate ON vs OFF behavior differs"; fail=1; fi
if ! printf '%s' "$on_run" | grep -qE "grow_sum=4995 alias_ok=true size=10 mut_sum=4689"; then
  echo "FAIL: gate-ON RESULT is not the expected correct value"; fail=1
fi

# (2) V3 SPECIFICALLY flipped (not value-proxy on other stdlib types):
#   (2a) V3 is ABIFACTS ELIGIBLE with stride-geps.
if ! grep -qE "^\[ABIFACTS\]   ELIGIBLE V3 " "$TMP_DIR/on.facts"; then
  echo "FAIL: V3 is not ABIFACTS ELIGIBLE (the intended target was not flipped)"; fail=1
fi
if ! grep -qE "^\[ABIFACTS\]   stride-geps V3=[1-9]" "$TMP_DIR/on.facts"; then
  echo "FAIL: V3 has no stride-geps (no inline @buffer geps)"; fail=1
fi
#   (2b) ivc_raw appears INSIDE Array(V3)# functions (not just globally), and
#        Array(V3)#delete_at uses the inline ptr_move stride (12 = sizeof V3), not 8.
ADAMAS_INLINE_VALUE_ARRAY_STORAGE=1 "$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/on_ir" >/dev/null 2>/dev/null || true
v3_ivc="$(awk '/^define/{inv=($0 ~ /Array.LV3.R.H/)} inv&&/ivc_raw/{c++} END{print c+0}' "$TMP_DIR/on_ir.ll")"
if [[ "$v3_ivc" -lt 1 ]]; then
  echo "FAIL: no ivc_raw inside any Array(V3)# function (V3 not actually inline-stored)"; fail=1
fi
da="$(grep -nE "^define.*Array.LV3.R.H.*delete_at" "$TMP_DIR/on_ir.ll" | head -1 | cut -d: -f1 || true)"
if [[ -n "$da" ]]; then
  body="$(awk -v s="$da" 'NR>=s && NR<=s+80{print} NR>s && /^}/{exit}' "$TMP_DIR/on_ir.ll")"
  if printf '%s' "$body" | grep -qE "__adamas_ptr_move\(.*i32 8\)"; then
    echo "FAIL: Array(V3)#delete_at still uses legacy ptr_move stride i32 8"; fail=1
  fi
  if ! printf '%s' "$body" | grep -qE "__adamas_ptr_move\(.*i32 12\)"; then
    echo "FAIL: Array(V3)#delete_at does not use inline ptr_move stride i32 12"; fail=1
  fi
fi

# (3) gate OFF emits no ivc_raw (behavior fully gated).
"$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/off_ir" >/dev/null 2>/dev/null || true
if [[ "$(grep -c ivc_raw "$TMP_DIR/off_ir.ll" || true)" != "0" ]]; then
  echo "FAIL: gate-OFF IR has ivc_raw — behavior leaked when gate off"; fail=1
fi

if [[ $fail -ne 0 ]]; then echo "tmp_dir: $TMP_DIR"; exit 1; fi
echo "ok: Array(V3) inline-stored (ELIGIBLE, stride-geps, ivc_raw in Array(V3)# fns=$v3_ivc, delete_at ptr_move i32 12); behavior-identical to legacy; gate-OFF clean"
exit 0
