#!/usr/bin/env bash
# KNOWN-BUG reproducer (currently FAILS with SIGSEGV): the String#split nilable-`limit`
# MONOMORPHIZATION COLLISION that is the ROOT of the s2b startup crash. A program with
# both an Int32-limit Char split and a nil-limit Char split monomorphizes the shared
# `String#split$Char$$arity3_block` with `i32 %limit`; the nil-limit wrapper then does
# an unguarded `load i32, ptr %limit` on a NULL pointer -> crash. Asserts the CORRECT
# behavior (a=2, b=4, no crash); will pass once the nilable-limit lowering is fixed.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
SRC="regression_tests/string_split_int32_nil_limit_collision_repro.cr"
RUNNER="${RUNNER:-scripts/run_safe.sh}"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/splitcoll.XXXXXX")"
cleanup() { [[ "$KEEP_TMP" != "1" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT
[[ -f "$SRC" ]] || { echo "missing reducer source: $SRC"; exit 2; }

"$COMPILER" "$SRC" -o "$TMP_DIR/bin" >/dev/null 2>/dev/null
run="$("$RUNNER" "$TMP_DIR/bin" 5 256 2>&1 | grep RESULT || true)"
echo "compiler: $COMPILER"
echo "  ${run:-<no RESULT: crashed>}"

fail=0
if [[ -z "$run" ]]; then echo "KNOWN BUG: missing RESULT (nilable-limit collision SIGSEGV)"; fail=1; fi
# CORRECT behavior: Int32-limit split('/', 2) -> 2 parts; nil-limit remove_empty -> 4 parts.
if ! printf '%s' "$run" | grep -qE "int_limit=2 "; then
  echo "FAIL: split('/', 2) wrong count (expected int_limit=2)"; fail=1
fi
if ! printf '%s' "$run" | grep -qE "nil_limit=4"; then
  echo "KNOWN BUG: split('/', remove_empty: true) wrong/crash (expected nil_limit=4)"; fail=1
fi

[[ $fail -ne 0 ]] && { echo "tmp_dir: $TMP_DIR"; exit 1; }
echo "ok: Int32-limit and nil-limit Char splits coexist without the monomorphization collision"
exit 0
