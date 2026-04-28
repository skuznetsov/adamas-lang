#!/usr/bin/env bash
# Regression test for nilable-arg `==`/`!=` STUB.
# Before fix: emit_binary_call for `Char#==(Nil | Char)` mangled to
# `Char#==$Nil | Char` and emitted a direct Call HIR node, bypassing
# `try_emit_union_arg_dispatch` (which only fires for 2+ non-Nil variants
# anyway). At LLVM the call resolved to a STUB (`STUB CALLED:
# $EQ$Nil$_$OR$_Char`) and aborted at runtime.
#
# Trigger path: `@name[0]?.in?({'/', '.'})` desugars via Object#in?(Tuple)
# to `Tuple#includes?(Nil|Char)`. lower_tuple_includes_intrinsic then
# emits per-element `tuple[i] == needle` where needle is `Nil|Char`.
# Without the dispatch synthesis, every tuple-element comparison hit a
# stub.
#
# Fix: in emit_binary_call, when op is `==`/`!=` and the right operand
# type is `Nil | T` (exactly Nil + one non-Nil variant), synthesize:
#   union_is(right, Nil) ? <nil-result> : (left OP unwrap(right))
# where nil-result is `false` for `==` and `true` for `!=`. The recursive
# call lands on `left.OP(T)` which has a real overload.
set -euo pipefail

COMPILER="${1:-./bin/crystal_v2}"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nilable_eq.XXXXXX")"
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
# `Tuple#includes?(Nil|Char)` via Object#in?
sep = {'/', '.'}
n = "ab"
r = n[0]?     # Char ('a')
puts(r.in?(sep) ? "yes" : "no")  # 'a'.in?({'/', '.'}) => false
r2 = ""[0]?   # Nil
puts(r2.in?(sep) ? "yes" : "no") # nil.in?(...) via includes? => false
r3 = "/abc"[0]?  # Char ('/')
puts(r3.in?(sep) ? "yes" : "no") # '/'.in?({'/', '.'}) => true
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

expected=$'no\nno\nyes'

if [[ "$stdout_text" == "$expected" ]]; then
  echo "fixed: nilable Char|Nil dispatch synthesized in == binary call"
  exit 0
fi

echo "unexpected output (expected: no, no, yes)"
cat "$RUN_OUT"
exit 1
