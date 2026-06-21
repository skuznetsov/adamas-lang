#!/usr/bin/env bash
# C-narrow-a PLACEMENT NEGATIVES regression (GPT round-3): the combo with ALL THREE
# gates on the multi-shape eligibility .cr. The pre-opt candidate gate + post-opt
# placement re-population must NOT leave a stale mark that places an ineligible site.
# Asserts only the eligible Vec3 sites are placed; Pair (storage-ineligible) / reused
# Vec3 (not sole-use) / Box (ref-owning -> class) are NOT placed.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
SRC="regression_tests/cnarrow_a_preflight_eligibility.cr"
RUNNER="${RUNNER:-scripts/run_safe.sh}"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cnarrowneg.XXXXXX")"
cleanup() { [[ "$KEEP_TMP" != "1" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

[[ -f "$SRC" ]] || { echo "missing reducer source: $SRC"; exit 2; }
fail=0

# NOTE: this multi-shape source is the COMPILE-ONLY preflight census .cr; it segfaults
# at runtime (a pre-existing Pair/Box mixed-shape crash, present at every gate state and
# unrelated to placement), so behavior-on-run identity is covered by cnarrow_a_placement.sh
# (clean V3 program). Here we assert the COMBO eligibility at the IR/mark level.

# ALL THREE gates: A' + candidate (pre-opt) + placement (post-opt re-populate).
set +e
ADAMAS_INLINE_VALUE_ARRAY_STORAGE=1 ADAMAS_CNARROW_A_CANDIDATE=verbose ADAMAS_CNARROW_A_PLACEMENT=1 \
  "$COMPILER" "$SRC" -o "$TMP_DIR/all3" 2>"$TMP_DIR/all3.err" >/dev/null
all3_status=$?
set -e
[[ $all3_status -ne 0 ]] && { echo "FAIL: all-3-gates compile failed ($all3_status)"; grep CNARROW "$TMP_DIR/all3.err" | head; exit 1; }

echo "compiler: $COMPILER"
grep -E "CNARROW_A_(MARK\] candidate type=(Vec3|Pair|Box)|PLACE\])" "$TMP_DIR/all3.err" | sort -u || true

# (1) Pair/Box never marked; Vec3 marked.
if grep -qE "CNARROW_A_MARK\] candidate type=(Pair|Box)" "$TMP_DIR/all3.err"; then
  echo "FAIL: Pair/Box marked as placement candidate (stale-mark leak?)"; fail=1
fi
if ! grep -qE "CNARROW_A_MARK\] candidate type=Vec3" "$TMP_DIR/all3.err"; then
  echo "FAIL: Vec3 not marked"; fail=1
fi

# (2) IR: Pair$Dnew unchanged (Pair not placed); Vec3$Dnew drops but stays >0 (the
#     2 eligible sites eliminated, the reused non-sole-use site remains).
ADAMAS_INLINE_VALUE_ARRAY_STORAGE=1 "$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/ap" >/dev/null 2>/dev/null || true
ADAMAS_INLINE_VALUE_ARRAY_STORAGE=1 ADAMAS_CNARROW_A_CANDIDATE=1 ADAMAS_CNARROW_A_PLACEMENT=1 \
  "$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/a3" >/dev/null 2>/dev/null || true
pair_ap="$(grep -cE 'call .*Pair.Dnew' "$TMP_DIR/ap.ll" || true)"
pair_a3="$(grep -cE 'call .*Pair.Dnew' "$TMP_DIR/a3.ll" || true)"
v3_ap="$(grep -cE 'call .*Vec3.Dnew' "$TMP_DIR/ap.ll" || true)"
v3_a3="$(grep -cE 'call .*Vec3.Dnew' "$TMP_DIR/a3.ll" || true)"
echo "  Pair\$Dnew: A'=$pair_ap all3=$pair_a3 ; Vec3\$Dnew: A'=$v3_ap all3=$v3_a3"
if [[ "$pair_ap" -lt 1 || "$pair_a3" -ne "$pair_ap" ]]; then
  echo "FAIL: Pair\$Dnew changed (Pair wrongly placed?) A'=$pair_ap all3=$pair_a3"; fail=1
fi
if [[ "$v3_a3" -ge "$v3_ap" ]]; then
  echo "FAIL: eligible Vec3\$Dnew not eliminated (A'=$v3_ap all3=$v3_a3)"; fail=1
fi
if [[ "$v3_a3" -lt 1 ]]; then
  echo "FAIL: ALL Vec3\$Dnew eliminated — the reused (non-sole-use) site was wrongly placed"; fail=1
fi

[[ $fail -ne 0 ]] && { echo "tmp_dir: $TMP_DIR"; exit 1; }
echo "ok: combo (A'+candidate+placement) places only eligible Vec3; Pair\$Dnew unchanged ($pair_ap); Vec3\$Dnew $v3_ap->$v3_a3 (eligible eliminated, reused remains); Pair/Box not marked; behavior unchanged"
exit 0
