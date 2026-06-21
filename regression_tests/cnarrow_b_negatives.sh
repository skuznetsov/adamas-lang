#!/usr/bin/env bash
# C-narrow-b NEGATIVE coverage regression (GPT blocker 3): none of the carrier-required
# V3 shapes (direct/alias arr[i]=, delete_at/shift/insert, cross-block) may be marked
# eligible; the carrier reasons must fire. Behavior-neutral (preflight under A').
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
SRC="regression_tests/cnarrow_b_negatives.cr"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cnbneg.XXXXXX")"
ERR="$TMP_DIR/neg.err"
cleanup() { [[ "$KEEP_TMP" != "1" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

[[ -f "$SRC" ]] || { echo "missing reducer source: $SRC"; exit 2; }

set +e
ADAMAS_INLINE_VALUE_ARRAY_STORAGE=1 ADAMAS_CNARROW_B_PREFLIGHT=1 "$COMPILER" "$SRC" -o "$TMP_DIR/bin" >/dev/null 2>"$ERR"
status=$?
set -e
[[ $status -ne 0 ]] && { echo "preflight compile failed ($status); tmp_dir=$TMP_DIR"; grep CNARROW_B "$ERR" | head; exit 2; }

echo "compiler: $COMPILER"
v3="$(grep -E "^\[CNARROW_B\]   V3 \| " "$ERR" | head -1 || true)"
echo "  $v3"

fail=0
[[ -z "$v3" ]] && { echo "FAIL: no V3 per-type row"; fail=1; }

# NO V3 load may be eligible in this pure-negative source.
if printf '%s' "$v3" | grep -qE "eligible=[1-9]"; then
  echo "FAIL: a carrier-required V3 shape was marked eligible (fail-closed breached)"; fail=1
fi
# the carrier reasons must fire.
if ! printf '%s' "$v3" | grep -qE "intervening_mutation=[1-9]"; then
  echo "FAIL: direct/alias arr[i]= not caught as intervening_mutation"; fail=1
fi
if ! printf '%s' "$v3" | grep -qE "intervening_call=[1-9]"; then
  echo "FAIL: delete_at/shift/insert not caught as intervening_call"; fail=1
fi
if ! printf '%s' "$v3" | grep -qE "cross_block=[1-9]"; then
  echo "FAIL: cross-block use not caught as cross_block"; fail=1
fi

# behavior neutrality (under A').
ADAMAS_INLINE_VALUE_ARRAY_STORAGE=1 "$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/off" >/dev/null 2>/dev/null || true
ADAMAS_INLINE_VALUE_ARRAY_STORAGE=1 ADAMAS_CNARROW_B_PREFLIGHT=1 "$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/on" >/dev/null 2>/dev/null || true
sed -E 's/stub_name_[0-9a-fA-F]+/stub_name_N/g' "$TMP_DIR/off.ll" > "$TMP_DIR/off.norm.ll"
sed -E 's/stub_name_[0-9a-fA-F]+/stub_name_N/g' "$TMP_DIR/on.ll"  > "$TMP_DIR/on.norm.ll"
nd="$(diff "$TMP_DIR/off.norm.ll" "$TMP_DIR/on.norm.ll" | grep -c '^[<>]' || true)"
[[ "$nd" != "0" ]] && { echo "FAIL: preflight ON vs OFF IR differs ($nd lines)"; fail=1; }

[[ $fail -ne 0 ]] && { echo "tmp_dir: $TMP_DIR"; exit 1; }
echo "ok: no carrier-required V3 shape marked eligible; intervening_mutation + intervening_call + cross_block all fire; behavior-neutral (IR diff=0)"
exit 0
