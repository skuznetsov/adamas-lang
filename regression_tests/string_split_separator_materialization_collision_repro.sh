#!/usr/bin/env bash
# Regression: a String-separator split materialized the Char-separator def when a
# Char split coexisted in the same program (def-registry lookup picked the
# global-best-scoring overload across ALL recorded call-entries, ignoring the
# requested mangled name's own type suffix). `"x#y".split("#")` returned 1 instead
# of 2 whenever a `split(Char, ...)` call coexisted. Root + fix:
# docs/string_split_overload_and_nil_limit_census.md ("mangled_prefix_typed_untyped
# ignores requested name's type suffix" / re-select). NOT the Bug 1 overload
# misdispatch (that is single-arg split(Char) -> whitespace; tracked separately).
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/string_split_sep_mat_collision.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
COMPILE_ERR="$TMP_DIR/compile.err"
RUN_OUT="$TMP_DIR/run.out"
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$SRC" <<'CR'
# Char-separator split with a limit (uses the Char overload)
a = "a/b/c/d".split('/', 2)
# String-separator split (must NOT inherit the Char materialization)
b = "x#y".split("#")
puts "RESULT=#{a.size},#{b.size}"
CR

# The collision only manifests under the per-shape block specialization gate.
export ADAMAS_BLOCK_SHAPE_SPECIALIZE=1

set +e
"$COMPILER" "$SRC" -o "$BIN" >/dev/null 2>"$COMPILE_ERR"
compile_status=$?
set -e
if [[ $compile_status -ne 0 ]]; then
  echo "FAIL: compile failed (status $compile_status)"
  cat "$COMPILE_ERR"
  exit 2
fi

set +e
./scripts/run_safe.sh "$BIN" 10 512 >"$RUN_OUT" 2>&1
set -e

result_line="$(grep -E '^RESULT=' "$RUN_OUT" | head -1)"
expected="RESULT=2,2"
if [[ "$result_line" == "$expected" ]]; then
  echo "PASS: coexisting Char-limit and String-separator splits both materialize correctly"
  exit 0
else
  echo "FAIL: String-separator split collided with the Char materialization"
  echo "expected: $expected (Char-limit split=2, String split=2)"
  echo "actual:   ${result_line:-<no RESULT line>}"
  exit 1
fi
