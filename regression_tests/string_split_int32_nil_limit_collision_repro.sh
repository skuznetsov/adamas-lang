#!/usr/bin/env bash
# GATED-FIX validator for String#split nilable-`limit` MONOMORPHIZATION COLLISION (Bug 2).
#
# The bug: a program with both an Int32-limit Char split and a nil-limit Char split
# monomorphizes the shared `String#split$Char$$arity3_block` to ONE `%limit` repr; the
# mismatched wrapper then coerces (Int32 via `inttoptr ... to ptr`, or Nil via an unguarded
# `load i32, ptr %limit` on NULL) -> wrong count / SIGSEGV.
#
# The fix is GATED behind ADAMAS_BLOCK_SHAPE_SPECIALIZE=1 (per-shape block specialization):
# distinct `Char_Int32_Bool_block`(i32 limit) and `Char_Nil_Bool_block`(ptr limit) defines,
# no cross-repr coercion. This script runs the reducer WITH the gate ON and asserts the
# correct result (int_limit=2 nil_limit=4, no crash). It is an EXPLICIT GATED check, not a
# "default fixed" claim:
#   - gate ON  (this script): GREEN once the fix is present.
#   - gate OFF (default):     still RED (pre-existing SIGSEGV) -- see the gate-OFF note below.
# This fix does NOT make the self-host s2b clean: s2b now progresses PAST the Globber/
# String#split startup crash to a SEPARATE backend `@value_def_block` crash in
# LLVMIRGenerator#emit_function. Bug 1 (single-Char-arg `split('/')` overload misdispatch,
# string_split_default_nil_limit_repro) is also separate and still open.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
SRC="regression_tests/string_split_int32_nil_limit_collision_repro.cr"
RUNNER="${RUNNER:-scripts/run_safe.sh}"
KEEP_TMP="${KEEP_TMP:-0}"
# Default to the gated mode so this reducer is a real PASS/FAIL check of the fix, not a
# perpetually-red "known bug". Override with GATE=0 to observe the pre-existing crash.
GATE="${GATE:-1}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/splitcoll.XXXXXX")"
cleanup() { [[ "$KEEP_TMP" != "1" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT
[[ -f "$SRC" ]] || { echo "missing reducer source: $SRC"; exit 2; }

ADAMAS_BLOCK_SHAPE_SPECIALIZE="$GATE" "$COMPILER" "$SRC" -o "$TMP_DIR/bin" >/dev/null 2>/dev/null
run="$("$RUNNER" "$TMP_DIR/bin" 5 256 2>&1 | grep RESULT || true)"
echo "compiler: $COMPILER (ADAMAS_BLOCK_SHAPE_SPECIALIZE=$GATE)"
echo "  ${run:-<no RESULT: crashed>}"

if [[ "$GATE" == "0" ]]; then
  # Gate-OFF baseline: the collision is expected (pre-existing). Report, do not fail.
  echo "note: gate OFF -> pre-existing collision baseline (expected red); rerun with GATE=1 for the fix"
  exit 0
fi

fail=0
if [[ -z "$run" ]]; then echo "FAIL: missing RESULT (nilable-limit collision SIGSEGV under gate ON)"; fail=1; fi
# CORRECT behavior: Int32-limit split('/', 2) -> 2 parts; nil-limit remove_empty -> 4 parts.
if ! printf '%s' "$run" | grep -qE "int_limit=2 "; then
  echo "FAIL: split('/', 2) wrong count (expected int_limit=2)"; fail=1
fi
if ! printf '%s' "$run" | grep -qE "nil_limit=4"; then
  echo "FAIL: split('/', remove_empty: true) wrong/crash (expected nil_limit=4)"; fail=1
fi

[[ $fail -ne 0 ]] && { echo "tmp_dir: $TMP_DIR"; exit 1; }
echo "ok (gated): Int32-limit and nil-limit Char splits coexist without the monomorphization collision"
exit 0
