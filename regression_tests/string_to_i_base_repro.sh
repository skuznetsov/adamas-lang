#!/usr/bin/env bash
# Regression test for String#to_i(base) honoring the base argument.
#
# Before fix, the `String#to_i` / `to_i32` interception in lower_call
# (ast_to_hir.cr) emitted `__adamas_string_to_i(receiver)` for ANY argument
# count ("match any args count"), dropping the base argument entirely. The
# intrinsic hardcoded base 10 (strtol(..., 10)), so every non-decimal
# conversion silently parsed as decimal:
#   "ff".to_i(16) -> 0   (should be 255)
#   "101".to_i(2) -> 101 (should be 5)
#   "z".to_i(36)  -> 0   (should be 35)
#
# Fix: when a base argument is present, route to a base-aware intrinsic
# (__adamas_string_to_i_base) that passes the base to strtol's runtime base
# parameter. The no-argument decimal fast path is unchanged.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/to_i_base.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
COMPILE_OUT="$TMP_DIR/compile.out"
COMPILE_ERR="$TMP_DIR/compile.err"
RUN_OUT="$TMP_DIR/run.out"

cleanup() {
  if [[ "$KEEP_TMP" != "1" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

cat >"$SRC" <<'CR'
STDERR.puts "hex_ff=#{"ff".to_i(16)}"   # 255
STDERR.puts "hex_c=#{"c".to_i(16)}"     # 12
STDERR.puts "bin_101=#{"101".to_i(2)}"  # 5
STDERR.puts "b36_z=#{"z".to_i(36)}"     # 35
STDERR.puts "oct_17=#{"17".to_i(8)}"    # 15
STDERR.puts "dec_42=#{"42".to_i}"       # 42 (no base, decimal fast path)
STDERR.flush
CR

set +e
"$COMPILER" "$SRC" -o "$BIN" >"$COMPILE_OUT" 2>"$COMPILE_ERR"
compile_status=$?
set -e

if [[ $compile_status -ne 0 ]]; then
  echo "compile failed"
  echo "compiler: $COMPILER"
  echo "status: $compile_status"
  echo "tmp_dir: $TMP_DIR"
  echo "--- stderr ---"
  cat "$COMPILE_ERR"
  echo "--- stdout ---"
  cat "$COMPILE_OUT"
  exit 2
fi

./scripts/run_safe.sh "$BIN" 5 256 >"$RUN_OUT"
stderr_text="$(awk '/^=== STDERR ===/{flag=1;next}/^\[EXIT/{flag=0}flag' "$RUN_OUT" | tr -d '\r' | sed '/^$/d')"

echo "compiler: $COMPILER"
echo "tmp_dir: $TMP_DIR"
echo "stderr:"
printf '%s\n' "$stderr_text"

expected="hex_ff=255
hex_c=12
bin_101=5
b36_z=35
oct_17=15
dec_42=42"

if [[ "$stderr_text" == "$expected" ]]; then
  echo "fixed: String#to_i(base) honors the base argument"
  exit 0
fi

echo "unexpected output (expected):"
printf '%s\n' "$expected"
cat "$RUN_OUT"
exit 1
