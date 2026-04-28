#!/usr/bin/env bash
# Regression test for case-in multi-variant pattern unions.
# Before fix: `in B | C | D` reduced to constant false at compile time,
# so all branches fell through and nothing matched.
# Two root causes (commit 4b0e32f7):
#   1) extract_type_name_from_node ignored BinaryNode `|` operator.
#   2) emit_is_a_check_for_type iterated empty type_params for unions
#      instead of @union_descriptors.variants.
set -euo pipefail

COMPILER="${1:-./bin/crystal_v2}"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/case_in_pattern_union.XXXXXX")"
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
struct A; def initialize; end; end
struct B; def initialize; end; end
struct C; def initialize; end; end
struct D; def initialize; end; end

x : A | B | C | D = B.new
case x
in A
  puts "A"
in B | C | D
  puts "BCD"
end

y : A | B | C | D = C.new
case y
in A
  puts "A"
in B | C | D
  puts "BCD"
end

z : A | B | C | D = D.new
case z
in A
  puts "A"
in B | C | D
  puts "BCD"
end
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
stdout_text="$(awk '/^=== STDOUT ===/{flag=1;next}/^=== STDERR ===/{flag=0}flag' "$RUN_OUT" | tr -d '\r')"

echo "compiler: $COMPILER"
echo "tmp_dir: $TMP_DIR"
echo "stdout:"
printf '%s\n' "$stdout_text"

expected=$'BCD\nBCD\nBCD'

if [[ "$stdout_text" == "$expected" ]]; then
  echo "fixed: case-in pattern unions match each variant correctly"
  exit 0
fi

echo "unexpected output"
cat "$RUN_OUT"
exit 1
