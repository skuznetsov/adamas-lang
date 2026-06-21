#!/usr/bin/env bash
# Diagnostic regression for the C-decision LOAD-SIDE consumption census.
#
# The read-only census (gate ADAMAS_STRUCT_BYVALUE_LOADSIDE_CENSUS) classifies how
# every loaded InlineValueCopy struct value is consumed, by a fail-closed escape
# walk: stack_local / recv_borrow / heap:<reason>. This separates C-narrow (only
# stack-eligible loads can drop the A' heap carrier) from C-wide (the rest need the
# by-value call/return/union ABI).
#
# The probe struct V3 is wired to hit ALL FOUR verdict classes in one compile:
#   (1) stack_local   : `v = arr[j]; acc += v.a+v.b+v.c`  (fields read locally)
#   (2) recv_borrow   : `arr[k].total`                     (loaded value = receiver)
#   (3) heap:passed_arg: `sink << arr[2]`                  (loaded value pushed away)
#   (4) heap:returned : `first_elem(arr)` returns `arr[0]` (escapes the frame)
#
# Asserts:
#   - V3 per-element row has stack_local>=1 AND recv_borrow>=1 AND heap>=1
#     (the classifier DISCRIMINATES the classes, not a degenerate all-one-bucket).
#   - the designed escapes appear: a heap:passed_arg AND a heap:returned verdict.
#   - user-level heap_carrier_required >= 1 (escapes are detected, not swallowed).
#   - GATE NEUTRALITY: census ON vs OFF LLVM IR byte-identical once the pre-existing
#     non-deterministic @.stub_name_<hash> symbols are normalized (read-only).
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
SRC="regression_tests/loadside_consumption_census_probe.cr"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/loadside.XXXXXX")"
ERR="$TMP_DIR/census.err"
LL_OFF="$TMP_DIR/off.norm.ll"
LL_ON="$TMP_DIR/on.norm.ll"

cleanup() { [[ "$KEEP_TMP" != "1" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

if [[ ! -f "$SRC" ]]; then
  echo "missing reducer source: $SRC"
  exit 2
fi

set +e
ADAMAS_STRUCT_BYVALUE_LOADSIDE_CENSUS=1 "$COMPILER" "$SRC" -o "$TMP_DIR/bin" >/dev/null 2>"$ERR"
status=$?
set -e
if [[ $status -ne 0 ]]; then
  echo "census compile failed (status $status); tmp_dir=$TMP_DIR"
  grep "LOADSIDE" "$ERR" || true
  exit 2
fi

echo "compiler: $COMPILER"
grep -E "LOADSIDE\]   (V3 |stack_local =|recv_borrow =|heap_carrier_required|stack_fast)" "$ERR" || true

fail=0

# (1) V3 per-element row discriminates all three columns: stack_local | recv_borrow | heap.
v3_row="$(grep -E "^\[LOADSIDE\]   V3 \| " "$ERR" | head -1 || true)"
if [[ -z "$v3_row" ]]; then
  echo "FAIL: no V3 per-element row emitted"
  fail=1
else
  sl="$(echo "$v3_row" | awk -F'|' '{gsub(/ /,"",$2); print $2}')"
  rb="$(echo "$v3_row" | awk -F'|' '{gsub(/ /,"",$3); print $3}')"
  hp="$(echo "$v3_row" | awk -F'|' '{gsub(/ /,"",$4); print $4}')"
  if [[ "${sl:-0}" -lt 1 || "${rb:-0}" -lt 1 || "${hp:-0}" -lt 1 ]]; then
    echo "FAIL: V3 row does not discriminate all classes (stack_local=$sl recv_borrow=$rb heap=$hp)"
    fail=1
  fi
fi

# (2) the designed escapes are present.
if ! grep -qE "^\[LOADSIDE\]   heap:passed_arg = [1-9]" "$ERR"; then
  echo "FAIL: expected a heap:passed_arg verdict (the 'sink << arr[2]' push)"
  fail=1
fi
if ! grep -qE "^\[LOADSIDE\]   heap:returned = [1-9]" "$ERR"; then
  echo "FAIL: expected a heap:returned verdict (the first_elem return)"
  fail=1
fi

# (3) user-level escapes are detected.
heap_req="$(grep -oE "heap_carrier_required \(escapes\)\s+= [0-9]+" "$ERR" | grep -oE "[0-9]+$" || echo "0")"
if [[ "${heap_req:-0}" -lt 1 ]]; then
  echo "FAIL: expected user-level heap_carrier_required >= 1 (got ${heap_req:-none})"
  fail=1
fi

# (4) gate neutrality: ON vs OFF IR identical modulo stub-name hashes.
"$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/off" >/dev/null 2>/dev/null || true
ADAMAS_STRUCT_BYVALUE_LOADSIDE_CENSUS=1 "$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/on" >/dev/null 2>/dev/null || true
sed -E 's/stub_name_[0-9a-fA-F]+/stub_name_N/g' "$TMP_DIR/off.ll" > "$LL_OFF"
sed -E 's/stub_name_[0-9a-fA-F]+/stub_name_N/g' "$TMP_DIR/on.ll"  > "$LL_ON"
norm_diff="$(diff "$LL_OFF" "$LL_ON" | grep -c '^[<>]' || true)"
if [[ "$norm_diff" != "0" ]]; then
  echo "FAIL: census ON vs OFF IR differs ($norm_diff normalized lines) — census is not read-only"
  fail=1
fi

if [[ $fail -ne 0 ]]; then
  echo "tmp_dir: $TMP_DIR"
  exit 1
fi

echo "ok: V3 discriminates stack_local/recv_borrow/heap; heap:passed_arg + heap:returned present;"
echo "    user heap_carrier_required=$heap_req; census gate-neutral (normalized IR diff=0)"
exit 0
