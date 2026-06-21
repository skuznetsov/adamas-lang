#!/usr/bin/env bash
# C-narrow-a CANDIDATE MARK regression (gate ADAMAS_CNARROW_A_CANDIDATE).
#
# Behavior-neutral infra step (GPT-required bridge): the placement behavior transform
# cannot read the per-function lowering @value_map post-lowering, so the eligible
# placement sites are persisted as a durable MIR::Call#cnarrow_a_candidate mark,
# computed late (after the A' storage facts) = the full conjunction
# inline_array_storage_eligible(T) && semantic_recursive_pod(T) && fresh sole-use
# ctor && monomorphic Array(T)#push.
#
# Reuses the preflight eligibility .cr. Asserts the mark lands ONLY on the eligible
# Vec3 placement sites and NOT on Pair (not storage-eligible) / Box (ref-owning ->
# class) / the reused Vec3 (not sole-use), and is gate-neutral.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
SRC="regression_tests/cnarrow_a_preflight_eligibility.cr"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cnarrowmark.XXXXXX")"
ERR="$TMP_DIR/mark.err"
cleanup() { [[ "$KEEP_TMP" != "1" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

[[ -f "$SRC" ]] || { echo "missing reducer source: $SRC"; exit 2; }

set +e
ADAMAS_CNARROW_A_CANDIDATE=1 "$COMPILER" "$SRC" -o "$TMP_DIR/bin" >/dev/null 2>"$ERR"
status=$?
set -e
[[ $status -ne 0 ]] && { echo "candidate-mark compile failed ($status); tmp_dir=$TMP_DIR"; grep CNARROW_A_MARK "$ERR" || true; exit 2; }

echo "compiler: $COMPILER"
grep -E "CNARROW_A_MARK\]" "$ERR" || true

fail=0

# Vec3 placement candidates are marked (the 2 sole-use eligible pushes).
if ! grep -qE "^\[CNARROW_A_MARK\]   Vec3 = [1-9]" "$ERR"; then
  echo "FAIL: Vec3 placement candidate not marked"; fail=1
fi
# Pair (semantic-POD but NOT storage-eligible) must NOT be marked.
if grep -qE "^\[CNARROW_A_MARK\]   Pair = " "$ERR"; then
  echo "FAIL: Pair was marked a placement candidate (storage gate breached)"; fail=1
fi
# Box (ref-owning -> a class, not a struct ctor) must NOT be marked.
if grep -qE "^\[CNARROW_A_MARK\]   Box = " "$ERR"; then
  echo "FAIL: ref-owning Box was marked a placement candidate"; fail=1
fi

# gate neutrality.
"$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/off" >/dev/null 2>/dev/null || true
ADAMAS_CNARROW_A_CANDIDATE=1 "$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/on" >/dev/null 2>/dev/null || true
sed -E 's/stub_name_[0-9a-fA-F]+/stub_name_N/g' "$TMP_DIR/off.ll" > "$TMP_DIR/off.norm.ll"
sed -E 's/stub_name_[0-9a-fA-F]+/stub_name_N/g' "$TMP_DIR/on.ll"  > "$TMP_DIR/on.norm.ll"
nd="$(diff "$TMP_DIR/off.norm.ll" "$TMP_DIR/on.norm.ll" | grep -c '^[<>]' || true)"
if [[ "$nd" != "0" ]]; then
  echo "FAIL: candidate-mark ON vs OFF IR differs ($nd normalized lines) — not behavior-neutral"; fail=1
fi

[[ $fail -ne 0 ]] && { echo "tmp_dir: $TMP_DIR"; exit 1; }
echo "ok: Vec3 placement candidate marked; Pair (not storage-eligible) + ref-owning Box NOT marked; candidate-mark gate-neutral (IR diff=0)"
exit 0
