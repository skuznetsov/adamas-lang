#!/usr/bin/env bash
# C-narrow-a PREFLIGHT eligibility regression (gate ADAMAS_CNARROW_A_PREFLIGHT).
#
# Asserts the read-only preflight classifies each shape with the right reason under
# the CONJUNCTION gate (inline_array_storage_eligible && semantic_recursive_pod &&
# fresh sole-use ctor && monomorphic Array(T)#push), NOT semantic-POD alone:
#   Vec3 sole-use push     -> eligible
#   Vec3 ctor used twice    -> not_sole_use
#   Pair{Vec2,Vec2}         -> not_storage_eligible  (semantic-POD TRUE, storage FALSE
#                              -- the GPT Blocker-2 discriminator)
#   Box{String}             -> not_pod
# Plus gate neutrality (preflight ON vs OFF LLVM IR byte-identical modulo stub names).
#
# (erased_push is a reason the taxonomy carries for soundness but this compiler
#  monomorphizes all container access, so it is dormant -- not asserted >0.)
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
SRC="regression_tests/cnarrow_a_preflight_eligibility.cr"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cnarrowpre.XXXXXX")"
ERR="$TMP_DIR/pre.err"
cleanup() { [[ "$KEEP_TMP" != "1" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

[[ -f "$SRC" ]] || { echo "missing reducer source: $SRC"; exit 2; }

set +e
ADAMAS_CNARROW_A_PREFLIGHT=1 "$COMPILER" "$SRC" -o "$TMP_DIR/bin" >/dev/null 2>"$ERR"
status=$?
set -e
[[ $status -ne 0 ]] && { echo "preflight compile failed ($status); tmp_dir=$TMP_DIR"; grep CNARROW_A "$ERR" || true; exit 2; }

echo "compiler: $COMPILER"
grep -E "CNARROW_A\]   (eligible =|not_|Vec3 \||Pair \||Box \|)" "$ERR" || true

fail=0

if ! grep -qE "^\[CNARROW_A\]   eligible = [1-9]" "$ERR"; then
  echo "FAIL: no eligible sites"; fail=1
fi

v3="$(grep -E "^\[CNARROW_A\]   Vec3 \| " "$ERR" | head -1 || true)"
if ! printf '%s' "$v3" | grep -qE "eligible=[1-9]"; then
  echo "FAIL: Vec3 not classified eligible"; fail=1
fi
# the reused-ctor Vec3 site (w = Vec3.new; arr2 << w; use(w)) -> not_sole_use,
# detected only by following the SSA copy-closure.
if ! printf '%s' "$v3" | grep -qE "not_sole_use=[1-9]"; then
  echo "FAIL: Vec3 reused-ctor site not detected as not_sole_use (copy-closure follow)"; fail=1
fi
# Blocker-2 discriminator: semantic-POD TRUE but current Array storage NOT inline.
if ! grep -qE "^\[CNARROW_A\]   Pair \| .*not_storage_eligible=[1-9]" "$ERR"; then
  echo "FAIL: Pair not classified not_storage_eligible (Blocker-2 discriminator)"; fail=1
fi
# the not_pod reason is reachable (prelude struct-kind-but-non-POD types).
if ! grep -qE "^\[CNARROW_A\]   not_pod = [1-9]" "$ERR"; then
  echo "FAIL: not_pod reason never fires (taxonomy gap)"; fail=1
fi
# ref-owning Box must NOT be eligible (fail-closed; promoted to a class -> excluded).
if grep -qE "^\[CNARROW_A\]   Box \| .*eligible=" "$ERR"; then
  echo "FAIL: ref-owning Box was classified eligible (NOT fail-closed)"; fail=1
fi

# gate neutrality.
"$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/off" >/dev/null 2>/dev/null || true
ADAMAS_CNARROW_A_PREFLIGHT=1 "$COMPILER" --emit llvm-ir "$SRC" -o "$TMP_DIR/on" >/dev/null 2>/dev/null || true
sed -E 's/stub_name_[0-9a-fA-F]+/stub_name_N/g' "$TMP_DIR/off.ll" > "$TMP_DIR/off.norm.ll"
sed -E 's/stub_name_[0-9a-fA-F]+/stub_name_N/g' "$TMP_DIR/on.ll"  > "$TMP_DIR/on.norm.ll"
nd="$(diff "$TMP_DIR/off.norm.ll" "$TMP_DIR/on.norm.ll" | grep -c '^[<>]' || true)"
if [[ "$nd" != "0" ]]; then
  echo "FAIL: preflight ON vs OFF IR differs ($nd normalized lines) — not read-only"; fail=1
fi

[[ $fail -ne 0 ]] && { echo "tmp_dir: $TMP_DIR"; exit 1; }
echo "ok: Vec3 eligible + not_sole_use (copy-closure); Pair not_storage_eligible (semantic-POD but not inline-storage, Blocker-2); not_pod reachable; ref-owning Box not eligible; preflight gate-neutral (IR diff=0)"
exit 0
