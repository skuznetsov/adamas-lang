#!/usr/bin/env bash
# Regression: String#split(Char) returns the string UNSPLIT in V2 codegen.
#
# `"Box#initialize".split('#')` yields a 1-element array ["Box#initialize"]
# instead of ["Box", "initialize"]. The Char-delimiter overload is broken; the
# String-delimiter overload (`split("#")`) works. This is the ROOT of the s2b
# self-host crash in hir_type_is_lib_struct?: the self-hosted compiler computes
# `init_base_name.split('#').first` (ast_to_hir.cr lower_allocator_initializer_body
# ~29461/29922) to get the owner class for a constructor body; the broken split
# returns the full method name "Box#initialize" instead of "Box", so
# @current_class is set to a method full-name, @class_info[@current_class] misses,
# the ivar lookup is skipped, and the explicit `@items = ...` FieldSet gets a null
# type / offset 0 -> later MIR deref crashes. NOT the transparent-wrapper ABI.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/string_split_char_delimiter.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
COMPILE_ERR="$TMP_DIR/compile.err"
RUN_OUT="$TMP_DIR/run.out"
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$SRC" <<'CR'
a = "Box#initialize".split('#')   # Char overload (broken): expect ["Box","initialize"]
b = "x,y,z".split(',')            # Char overload (broken): expect 3 parts
c = "Box#initialize".split("#")   # String overload (control, works): expect 2 parts
puts "RESULT=#{a.size},#{a[0]},#{b.size},#{c.size}"
CR

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
expected="RESULT=2,Box,3,2"
if [[ "$result_line" == "$expected" ]]; then
  echo "PASS: String#split(Char) splits correctly"
  exit 0
else
  echo "FAIL: String#split(Char) miscompiled (Char overload returns unsplit)"
  echo "expected: $expected"
  echo "actual:   ${result_line:-<no RESULT line>}"
  exit 1
fi
