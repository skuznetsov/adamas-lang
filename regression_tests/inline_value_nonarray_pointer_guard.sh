#!/usr/bin/env bash
# A' behavior PREFLIGHT guard — the non-Array Pointer(T)#value path stays boxed.
#
# This is the invariant that the refuted type-driven slice violated. It must hold
# BEFORE behavior (baseline) and AFTER (when the inline-value Array storage slice
# lands). Asserts:
#   (1) RUNTIME: the program prints out=42 — the non-Array Pointer(Disc) value
#       load/store path computes correctly (it must keep working post-behavior).
#   (2) Disc is NOT inline_value_safe (it is never an Array element → bv=0).
#   (3) array_buffer_value gep marks land only inside Array(...) bodies (outside=0):
#       the Disc value GEP is NOT marked as an Array buffer access.
#   (4) The emitted IR carries no `ivc_raw` — no inline-value codegen fires on this
#       non-Array path (trivially true pre-behavior; the durable contract for after).
#
# When the behavior gate ADAMAS_INLINE_VALUE_ARRAY_STORAGE lands (which must itself
# run the annotation), re-point GATE below to it and re-confirm all four still hold.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
SRC="regression_tests/inline_value_nonarray_pointer_guard.cr"
RUNNER="${RUNNER:-scripts/run_safe.sh}"
GATE="${GATE:-ADAMAS_INLINE_VALUE_ANNOTATE}"   # re-point to ADAMAS_INLINE_VALUE_ARRAY_STORAGE
                                               # once it exists; that gate must also
                                               # emit [IVANNOT] (see behavior plan §1)
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ivguard.XXXXXX")"
ANN_ERR="$TMP_DIR/ann.err"
RUN_LOG="$TMP_DIR/run.log"

cleanup() {
  if [[ "$KEEP_TMP" != "1" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

if [[ ! -f "$SRC" ]]; then
  echo "missing reducer source: $SRC"
  exit 2
fi

# Compile under the gate (annotation or behavior). ADAMAS_IVC_VERIFY forces the
# [IVANNOT]/[ABIFACTS] evidence even under the behavior gate (where verify is
# otherwise opt-in), so the not-marked/not-eligible assertions work for both gates.
set +e
env "$GATE=1" ADAMAS_IVC_VERIFY=1 "$COMPILER" "$SRC" -o "$TMP_DIR/bin" >/dev/null 2>"$ANN_ERR"
status=$?
set -e
if [[ $status -ne 0 ]]; then
  echo "compile failed under $GATE (status $status); tmp_dir=$TMP_DIR"
  grep -E "IVANNOT|error" "$ANN_ERR" | head || true
  exit 2
fi

echo "compiler: $COMPILER   gate: $GATE"
fail=0

# (1) runtime: out=42 (run_safe.sh dumps child output to its stdout).
set +e
"$RUNNER" "$TMP_DIR/bin" 5 256 >"$RUN_LOG" 2>&1
set -e
if ! grep -qE "out=42" "$RUN_LOG"; then
  echo "FAIL: expected out=42 from the non-Array Pointer(Disc) path"
  grep -E "out=|TIMEOUT|KILLED|error" "$RUN_LOG" | head || true
  fail=1
fi

# (2) Disc not inline_value_safe.
if ! grep -qE "^\[IVANNOT\]   not-marked Disc$" "$ANN_ERR"; then
  echo "FAIL: Disc should be not-marked (never an Array element)"
  fail=1
fi
if grep -qE "^\[IVANNOT\]   SAFE-MARKED Disc$" "$ANN_ERR"; then
  echo "FAIL: Disc is SAFE-MARKED but must stay boxed (non-Array Pointer path)"
  fail=1
fi

# (3) array_buffer_value marks: outside an Array body MUST be 0.
outside="$(grep -E "array_buffer_value gep marks:" "$ANN_ERR" | grep -oE "outside=[0-9]+" | grep -oE "[0-9]+$" || echo "")"
if [[ "${outside:-x}" != "0" ]]; then
  echo "FAIL: array_buffer_value marks outside an Array body = '${outside:-none}' (MUST be 0)"
  fail=1
fi

# (4) Disc must NOT be behavior-eligible (so no inline ABI on its non-Array Pointer
# path). Under the behavior gate `ivc_raw` legitimately appears for OTHER eligible
# stdlib types, so a global grep is wrong — the gate-agnostic invariant is that Disc
# itself is never eligible (it has no Array(Disc) buffer_value access). Combined with
# out=42 (1) and not-marked (2), this proves the path stays boxed.
if grep -qE "^\[ABIFACTS\]   ELIGIBLE Disc " "$ANN_ERR"; then
  echo "FAIL: Disc is behavior-ELIGIBLE but must stay boxed (non-Array Pointer path)"
  fail=1
fi

if [[ $fail -ne 0 ]]; then
  echo "tmp_dir: $TMP_DIR"
  exit 1
fi

echo "ok: non-Array Pointer(Disc) path stays boxed — out=42, Disc not-marked/not-eligible, array_buffer_value outside=0"
exit 0
