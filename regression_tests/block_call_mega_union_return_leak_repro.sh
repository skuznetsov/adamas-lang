#!/usr/bin/env bash
# Regression test for the shared-generic `_block` mega-union STATIC return leak.
#
# Before fix: a block call on a concrete class receiver (here the implicit
# `fetch(index) { nil }` inside `Array(Nil|String)#[]?`) bound the MODULE-shared
# `Indexable(T)#fetch$Int32_block` function. That shared function's registered
# return type accretes the block returns + element types of EVERY Indexable
# call site in the program (a 17-variant mega-union: Nil|Char|Float32|...|
# String|...|UInt8). The call site inherited that mega-union as its STATIC
# type, so truthiness narrowing of `if t = names[0]?` enumerated wrong
# variants and union-arg overload dispatch emitted branches for types that
# can never occur (STUB CALLED: track2$Float32; in stage2: a scalar-variant
# branch extracted a 4-byte payload from a String and fed the 32-bit-truncated
# pointer to track_enum_value → EXC_BAD_ACCESS in lower_def).
#
# Fix (two layers in ast_to_hir.cr, both required):
# 1. preserve_receiver_block_call_target: block-call targets resolved to an
#    unresolved-generic owner (Indexable(T)) are re-qualified to the concrete
#    receiver (Array(Nil | String)#fetch$Int32_block) when the receiver names
#    exactly one runtime type (value kinds, or class kinds with no subclass).
# 2. infer_yield_return_type: inside a materialized `_block` function the
#    yield consults the `__block_return__` hint recorded under the function's
#    own exact mangled name first, instead of sliding to the module-shared
#    accreted entry.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/block_call_mega_union.XXXXXX")"
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
# `names[0]?` must type as Nil | String (element type of the receiver),
# not as the program-wide union of every Indexable block call's returns.
# With the mega-union leak, the narrowed overload dispatch below emitted
# branches for Char/Float32/... and aborted with STUB CALLED: track2$Float32.
def track2(s : String)
  STDERR.puts s
end

names = [] of String?
names << "hello"
if t = names[0]?
  track2(t)
end
STDERR.puts "done"
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
stderr_text="$(awk '/^=== STDERR ===/{flag=1;next}/^\[EXIT/{flag=0}flag' "$RUN_OUT" | tr -d '\r')"

echo "compiler: $COMPILER"
echo "tmp_dir: $TMP_DIR"
echo "stderr:"
printf '%s\n' "$stderr_text"

expected=$'hello\ndone'

if [[ "$stderr_text" == "$expected" ]]; then
  echo "fixed: block call bound receiver-specialized fetch with precise return type"
  exit 0
fi

echo "unexpected output (expected: hello, done)"
cat "$RUN_OUT"
exit 1
