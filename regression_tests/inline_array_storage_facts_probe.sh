#!/usr/bin/env bash
# A' mini-AbiFacts regression: Array bulk-op coverage facts (read-only).
#
# Gate ADAMAS_ARRAY_BULK_OP_FACTS classifies every Array(C) @buffer bulk op
# (move/copy/clear/alloc/realloc) inside monomorphic Array(C)# bodies by STRUCTURAL
# proof (@buffer provenance + element stride), persists ExternCall/Call#array_bulk_op
# and the composed Type#inline_array_storage_eligible, and verifies them.
#
# Asserts, in one compile of the reducer:
#   (1) Cov => ELIGIBLE — push/[]/delete_at/shift/insert/concat all classify as
#       covered (MoveCopySameElem / Clear / AllocRealloc), no Heterogeneous/Uncovered.
#   (2) Unc => ineligible with an Uncovered (or Heterogeneous) op — dup/reverse copy
#       into a fresh, non-self Array buffer the analysis cannot prove. This proves
#       the to_unsafe/fresh-malloc provenance refinement did NOT open a hole: an
#       unprovable bulk op still fail-closes the type.
#   (3) NO behavior: the emitted IR carries no `ivc_raw` and gate ON vs OFF LLVM IR
#       is byte-identical (normalized for the non-deterministic stub-name symbols).
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
SRC="regression_tests/inline_array_storage_facts_probe.cr"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/iasfacts.XXXXXX")"
ERR="$TMP_DIR/facts.err"
LL_OFF="$TMP_DIR/off.norm.ll"
LL_ON="$TMP_DIR/on.norm.ll"

cleanup() { [[ "$KEEP_TMP" != "1" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

if [[ ! -f "$SRC" ]]; then
  echo "missing reducer source: $SRC"
  exit 2
fi

set +e
ADAMAS_ARRAY_BULK_OP_FACTS=1 "$COMPILER" "$SRC" -o "$TMP_DIR/bin" >/dev/null 2>"$ERR"
status=$?
set -e
if [[ $status -ne 0 ]]; then
  echo "facts compile failed (status $status); tmp_dir=$TMP_DIR"
  grep -E "ABIFACTS|error" "$ERR" | head || true
  exit 2
fi

echo "compiler: $COMPILER"
grep -E "ABIFACTS\]   (ELIGIBLE Cov|ineligible Unc|ineligible Esc)" "$ERR" || true

fail=0

# (1) Cov ELIGIBLE, no Heterogeneous/Uncovered in its summary.
cov_line="$(grep -E "^\[ABIFACTS\]   (ELIGIBLE|ineligible) Cov " "$ERR" || true)"
if ! printf '%s' "$cov_line" | grep -qE "^\[ABIFACTS\]   ELIGIBLE Cov "; then
  echo "FAIL: Cov not ELIGIBLE"; echo "  got: $cov_line"; fail=1
fi
if printf '%s' "$cov_line" | grep -qE "Heterogeneous|Uncovered"; then
  echo "FAIL: Cov has a Heterogeneous/Uncovered op but is expected fully covered"; fail=1
fi

# (2) Unc ineligible with an Uncovered/Heterogeneous op (fail-closed proof).
unc_line="$(grep -E "^\[ABIFACTS\]   (ELIGIBLE|ineligible) Unc " "$ERR" || true)"
if ! printf '%s' "$unc_line" | grep -qE "^\[ABIFACTS\]   ineligible Unc "; then
  echo "FAIL: Unc not ineligible (fail-closed broken — refinement opened a hole)"; echo "  got: $unc_line"; fail=1
fi
if ! printf '%s' "$unc_line" | grep -qE "Uncovered|Heterogeneous"; then
  echo "FAIL: Unc ineligible but without an Uncovered/Heterogeneous reason"; fail=1
fi

# (2b) Esc ineligible — raw to_unsafe escape disqualifier (passed pointer, not vd).
esc_line="$(grep -E "^\[ABIFACTS\]   (ELIGIBLE|ineligible) Esc " "$ERR" || true)"
if ! printf '%s' "$esc_line" | grep -qE "^\[ABIFACTS\]   ineligible Esc "; then
  echo "FAIL: Esc not ineligible — raw to_unsafe escape was not disqualified"; echo "  got: $esc_line"; fail=1
fi

# (3a) no ivc_raw (no behavior).
ADAMAS_ARRAY_BULK_OP_FACTS=1 "$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/on" >/dev/null 2>/dev/null || true
"$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/off" >/dev/null 2>/dev/null || true
if grep -q "ivc_raw" "$TMP_DIR/on.ll"; then
  echo "FAIL: ivc_raw present — facts pass is not behavior-free"; fail=1
fi

# (3b) gate ON vs OFF IR byte-identical modulo stub-name hashes.
sed -E 's/stub_name_[0-9]+/stub_name_N/g' "$TMP_DIR/off.ll" > "$LL_OFF"
sed -E 's/stub_name_[0-9]+/stub_name_N/g' "$TMP_DIR/on.ll"  > "$LL_ON"
norm_diff="$(diff "$LL_OFF" "$LL_ON" | grep -c '^[<>]' || true)"
if [[ "$norm_diff" != "0" ]]; then
  echo "FAIL: facts ON vs OFF IR differs ($norm_diff normalized lines) — not read-only"; fail=1
fi

if [[ $fail -ne 0 ]]; then
  echo "tmp_dir: $TMP_DIR"; exit 1
fi

echo "ok: Cov ELIGIBLE (fully covered); Unc ineligible (Uncovered, fail-closed); no ivc_raw; gate-neutral (IR diff=0)"
exit 0
