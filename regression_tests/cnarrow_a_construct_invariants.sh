#!/usr/bin/env bash
# C-narrow-a CONSTRUCT-IN-PLACE invariant goldens (GPT review round 1, blocker 3).
#
# Pins the LEGACY (gate-OFF) runtime behavior the FUTURE C-narrow-a placement rewrite
# must preserve: (1) ctor args evaluated once and in source order; (2) grow/realloc
# preserves every element (capacity-before-write, size-after-init); (3) partial init
# invisible on a ctor raise. When the placement behavior lands (gated), re-run this
# WITH the behavior gate and assert the SAME RESULT line.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
SRC="regression_tests/cnarrow_a_construct_invariants.cr"
RUNNER="${RUNNER:-scripts/run_safe.sh}"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cnarrowinv.XXXXXX")"
cleanup() { [[ "$KEEP_TMP" != "1" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

[[ -f "$SRC" ]] || { echo "missing reducer source: $SRC"; exit 2; }

fail=0
"$COMPILER" "$SRC" -o "$TMP_DIR/bin" >/dev/null 2>/dev/null
run="$("$RUNNER" "$TMP_DIR/bin" 5 256 2>&1 | grep RESULT || true)"

echo "compiler: $COMPILER"
echo "  $run"

if [[ -z "$run" ]]; then echo "FAIL: missing RESULT (crash?)"; fail=1; fi
for k in order_ok grow_ok partial_ok; do
  if ! printf '%s' "$run" | grep -qE "${k}=true"; then
    echo "FAIL: invariant ${k} not satisfied by legacy lowering"; fail=1
  fi
done

[[ $fail -ne 0 ]] && { echo "tmp_dir: $TMP_DIR"; exit 1; }
echo "ok: C-narrow-a construct-in-place legacy goldens pinned (args once/in-order; grow preserves contents; partial-init invisible on raise)"
exit 0
