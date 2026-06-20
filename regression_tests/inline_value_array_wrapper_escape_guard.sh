#!/usr/bin/env bash
# A' BEHAVIOR negative guard: a USER wrapper escaping the Array buffer pointer keeps
# the element type INELIGIBLE (the synthetic-dispatcher exclusion must NOT open a
# real user escape). Asserts, under the behavior gate:
#   (1) WV is ABIFACTS ineligible (Box#leak → @a.to_unsafe is a real escape).
#   (2) no ivc_raw inside any Array(WV)# function (WV stays boxed/legacy).
#   (3) runtime works (boxed path is correct).
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
SRC="regression_tests/inline_value_array_wrapper_escape_guard.cr"
RUNNER="${RUNNER:-scripts/run_safe.sh}"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ivwrap.XXXXXX")"
cleanup() { [[ "$KEEP_TMP" != "1" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

if [[ ! -f "$SRC" ]]; then echo "missing reducer source: $SRC"; exit 2; fi
fail=0

ADAMAS_INLINE_VALUE_ARRAY_STORAGE=1 ADAMAS_IVC_VERIFY=1 "$COMPILER" "$SRC" -o "$TMP_DIR/bin" 2>"$TMP_DIR/facts" >/dev/null
echo "compiler: $COMPILER"
grep -E "ABIFACTS\]   (ELIGIBLE|ineligible) WV " "$TMP_DIR/facts" || true

# (1) WV ineligible.
if grep -qE "^\[ABIFACTS\]   ELIGIBLE WV " "$TMP_DIR/facts"; then
  echo "FAIL: WV is ELIGIBLE but a user wrapper escapes its buffer (must stay ineligible)"; fail=1
fi
if ! grep -qE "^\[IVANNOT\]   not-marked WV$|^\[ABIFACTS\]   ineligible WV " "$TMP_DIR/facts"; then
  echo "FAIL: WV not reported ineligible/not-marked"; fail=1
fi

# (2) no ivc_raw inside any Array(WV)# function.
ADAMAS_INLINE_VALUE_ARRAY_STORAGE=1 "$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/ir" >/dev/null 2>/dev/null || true
wv_ivc="$(awk '/^define/{inv=($0 ~ /Array.LWV.R.H/)} inv&&/ivc_raw/{c++} END{print c+0}' "$TMP_DIR/ir.ll")"
if [[ "$wv_ivc" != "0" ]]; then
  echo "FAIL: ivc_raw inside Array(WV)# functions ($wv_ivc) — WV was inline-stored despite the escape"; fail=1
fi

# (3) runtime works (boxed).
run="$("$RUNNER" "$TMP_DIR/bin" 5 256 2>&1 | grep -E "n=|ok=" || true)"
if ! printf '%s' "$run" | grep -qE "n=5 ok=true"; then
  echo "FAIL: runtime incorrect (expected n=5 ok=true): $run"; fail=1
fi

if [[ $fail -ne 0 ]]; then echo "tmp_dir: $TMP_DIR"; exit 1; fi
echo "ok: user-wrapper buffer escape keeps WV ineligible (0 ivc_raw in Array(WV)#); boxed runtime correct (n=5)"
exit 0
