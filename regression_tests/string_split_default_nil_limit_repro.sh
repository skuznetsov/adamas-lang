#!/usr/bin/env bash
# KNOWN-BUG reproducer (currently FAILS): String#split(Char) with the default nil limit
# returns 1 instead of the correct 4 -- the nilable-`limit` miscompile underlying the s2b
# startup crash (memory: s2b_startup_crash_split_glob_localization). Asserts the CORRECT
# behavior; will pass once the nilable-limit lowering is fixed.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
SRC="regression_tests/string_split_default_nil_limit_repro.cr"
RUNNER="${RUNNER:-scripts/run_safe.sh}"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/splitnil.XXXXXX")"
cleanup() { [[ "$KEEP_TMP" != "1" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT
[[ -f "$SRC" ]] || { echo "missing reducer source: $SRC"; exit 2; }

"$COMPILER" "$SRC" -o "$TMP_DIR/bin" >/dev/null 2>/dev/null
run="$("$RUNNER" "$TMP_DIR/bin" 5 256 2>&1 | grep RESULT || true)"
echo "compiler: $COMPILER"
echo "  $run"

fail=0
if [[ -z "$run" ]]; then echo "FAIL: missing RESULT (crash?)"; fail=1; fi
# CORRECT behavior: both splits of "a/b/c/d" by '/' yield 4 parts.
if ! printf '%s' "$run" | grep -qE "default=4 "; then
  echo "KNOWN BUG: split(Char) default nil limit returns the wrong count (expected default=4)"; fail=1
fi
if ! printf '%s' "$run" | grep -qE "remove_empty=4"; then
  echo "FAIL: split(Char, remove_empty: true) regressed (expected remove_empty=4)"; fail=1
fi

[[ $fail -ne 0 ]] && { echo "tmp_dir: $TMP_DIR"; exit 1; }
echo "ok: String#split(Char) default nil limit yields the correct part count"
exit 0
