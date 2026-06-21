#!/usr/bin/env bash
# C-narrow-a PLACEMENT behavior regression (gates ADAMAS_CNARROW_A_PLACEMENT +
# ADAMAS_INLINE_VALUE_ARRAY_STORAGE). Asserts:
#   - behavior identical: legacy == A'-only == A'+placement (same RESULT);
#   - placement happens: [CNARROW_A_PLACE] placed >= 1;
#   - the transient malloc disappears: __adamas_malloc64 count drops A'+placement vs
#     A'-only, and a stack alloc for V3 appears;
#   - A'-COUPLING GUARD: ADAMAS_CNARROW_A_PLACEMENT=1 WITHOUT A' => 0 placement.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
SRC="regression_tests/cnarrow_a_placement.cr"
RUNNER="${RUNNER:-scripts/run_safe.sh}"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cnarrowplace.XXXXXX")"
cleanup() { [[ "$KEEP_TMP" != "1" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

[[ -f "$SRC" ]] || { echo "missing reducer source: $SRC"; exit 2; }
fail=0

# Build + run: legacy (no gates), A' only, A' + placement.
"$COMPILER" "$SRC" -o "$TMP_DIR/legacy" >/dev/null 2>/dev/null
legacy_run="$("$RUNNER" "$TMP_DIR/legacy" 5 256 2>&1 | grep RESULT || true)"

ADAMAS_INLINE_VALUE_ARRAY_STORAGE=1 "$COMPILER" "$SRC" -o "$TMP_DIR/aprime" >/dev/null 2>/dev/null
aprime_run="$("$RUNNER" "$TMP_DIR/aprime" 5 256 2>&1 | grep RESULT || true)"

ADAMAS_INLINE_VALUE_ARRAY_STORAGE=1 ADAMAS_CNARROW_A_PLACEMENT=1 "$COMPILER" "$SRC" -o "$TMP_DIR/place" 2>"$TMP_DIR/place.err" >/dev/null
place_run="$("$RUNNER" "$TMP_DIR/place" 5 256 2>&1 | grep RESULT || true)"

echo "compiler: $COMPILER"
echo "  legacy: $legacy_run"
echo "  A':     $aprime_run"
echo "  place:  $place_run"
grep -E "CNARROW_A_PLACE\]" "$TMP_DIR/place.err" || true

# (1) behavior identity.
if [[ -z "$legacy_run" || -z "$place_run" ]]; then echo "FAIL: missing RESULT (crash?)"; fail=1; fi
if [[ "$legacy_run" != "$place_run" ]]; then echo "FAIL: A'+placement behavior differs from legacy"; fail=1; fi
if [[ "$aprime_run" != "$place_run" ]]; then echo "FAIL: A'+placement differs from A'-only"; fail=1; fi

# (2) placement happened (placed >= 1).
placed="$(grep -oE "placed=[0-9]+" "$TMP_DIR/place.err" | grep -oE "[0-9]+" | head -1 || echo 0)"
if [[ "${placed:-0}" -lt 1 ]]; then echo "FAIL: no placement performed (placed=${placed:-0})"; fail=1; fi

# (3) the transient heap allocator (V3$Dnew) CALL is eliminated at the placed site,
#     and a V3#initialize call (on the stack temp) replaces it. (The malloc lives
#     INSIDE the V3$Dnew body, which stays emitted as dead code, so the static
#     __adamas_malloc64 count is the wrong proxy; the eliminated CALL is the signal.)
ADAMAS_INLINE_VALUE_ARRAY_STORAGE=1 "$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/aprime_ir" >/dev/null 2>/dev/null || true
ADAMAS_INLINE_VALUE_ARRAY_STORAGE=1 ADAMAS_CNARROW_A_PLACEMENT=1 "$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/place_ir" >/dev/null 2>/dev/null || true
dnew_aprime="$(grep -cE 'call .*V3.Dnew' "$TMP_DIR/aprime_ir.ll" || true)"
dnew_place="$(grep -cE 'call .*V3.Dnew' "$TMP_DIR/place_ir.ll" || true)"
init_aprime="$(grep -cE 'call .*V3.*[Ii]nitialize' "$TMP_DIR/aprime_ir.ll" || true)"
init_place="$(grep -cE 'call .*V3.*[Ii]nitialize' "$TMP_DIR/place_ir.ll" || true)"
echo "  V3\$Dnew calls: A'=$dnew_aprime place=$dnew_place ; V3#init calls: A'=$init_aprime place=$init_place"
if [[ "$dnew_aprime" -lt 1 ]]; then echo "FAIL: A'-only has no V3\$Dnew call (reducer assumption broken)"; fail=1; fi
if [[ "$dnew_place" -ne 0 ]]; then echo "FAIL: V3\$Dnew transient call NOT eliminated by placement (place=$dnew_place)"; fail=1; fi
if [[ "$init_place" -le "$init_aprime" ]]; then echo "FAIL: placement did not add a V3#initialize on the stack temp"; fail=1; fi

# (4) A'-COUPLING GUARD: placement on WITHOUT A' => 0 placement.
ADAMAS_CNARROW_A_PLACEMENT=1 "$COMPILER" "$SRC" -o "$TMP_DIR/noaprime" 2>"$TMP_DIR/noaprime.err" >/dev/null
if grep -qE "CNARROW_A_PLACE\] marked=[0-9]+ placed=[1-9]" "$TMP_DIR/noaprime.err"; then
  echo "FAIL: placement happened WITHOUT A' (coupling breached -> UAF risk)"; fail=1
fi
noap_run="$("$RUNNER" "$TMP_DIR/noaprime" 5 256 2>&1 | grep RESULT || true)"
if [[ "$noap_run" != "$legacy_run" ]]; then echo "FAIL: placement-without-A' changed behavior"; fail=1; fi

[[ $fail -ne 0 ]] && { echo "tmp_dir: $TMP_DIR"; exit 1; }
echo "ok: placement behavior-identical (legacy==A'==place); placed=$placed; V3\$Dnew call $dnew_aprime->$dnew_place (transient eliminated); V3#init $init_aprime->$init_place; A'-coupling guard holds (placement off without A')"
exit 0
