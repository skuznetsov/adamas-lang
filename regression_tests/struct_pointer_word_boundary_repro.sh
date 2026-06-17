#!/usr/bin/env bash
# Regression: struct field storage at the pointer-word boundary (size == 8).
#
# The pointer-vs-inline storage decision for a struct field was made by THREE
# independent oracles with a boundary off-by-one:
#   - HIR  LayoutContract.user_struct_inline?  used  size >= POINTER_WORD_BYTES
#   - MIR  lower_field_get / lower_field_store  used  inline_size > pointer_word
# So a struct whose value is exactly one pointer word (8 bytes) was classified
# INLINE by HIR but a POINTER CARRIER by MIR. It was masked at runtime only
# because an 8-byte pointer and 8-byte inline value occupy the same slot size,
# but it was a latent repr-flip: the moment the constructor stores inline bytes
# (step-4), MIR's field-get would `load` the value bytes AS a pointer (the #4
# String<->Slice repr-flip family).
#
# Fix (ABI-rework 1c): route MIR lower_field_get/lower_field_store_to_ptr through
# the single layout source LayoutContract.user_struct_inline?, and align that
# predicate's threshold to `>` so the contract matches the behavioural readers.
# Behaviour-neutral (the LayoutProbe repr-decision set is byte-identical before
# and after), so this guard asserts the *runtime* round-trip of struct fields at
# the 4 / 8 / 16-byte sizes (8 is the boundary) stays correct.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/struct_pw_boundary.XXXXXX")"
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
# 4-byte struct value (< pointer word -> pointer carrier)
struct S4
  @x : Int32
  def initialize(@x); end
  def x; @x; end
end

# 8-byte struct value (== pointer word -> the boundary case)
struct S8
  @x : Int64
  def initialize(@x); end
  def x; @x; end
end

# 16-byte struct value (> pointer word -> inline)
struct S16
  @a : Int64
  @b : Int64
  def initialize(@a, @b); end
  def sum; @a + @b; end
end

class Holder
  @s4 : S4
  @s8 : S8
  @s16 : S16
  @marker : Int32
  def initialize(@s4, @s8, @s16, @marker); end
  def s4x; @s4.x; end       # field-get then inner getter
  def s8x; @s8.x; end       # boundary: read back exactly as written
  def s16sum; @s16.sum; end
  def marker; @marker; end
end

h = Holder.new(S4.new(41), S8.new(8_000_000_001_i64), S16.new(100_i64, 23_i64), 7777)
STDERR.puts "s4=#{h.s4x} s8=#{h.s8x} s16=#{h.s16sum} marker=#{h.marker}"
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

# s8 uses an 8-byte value that does NOT fit in 32 bits, so a wrong
# load-as-pointer / truncation at the boundary would corrupt it.
expected="s4=41 s8=8000000001 s16=123 marker=7777"

if [[ "$stderr_text" == "$expected" ]]; then
  echo "ok: struct fields round-trip at 4/8/16-byte sizes (pointer-word boundary)"
  exit 0
fi

echo "unexpected output (expected: $expected)"
cat "$RUN_OUT"
exit 1
