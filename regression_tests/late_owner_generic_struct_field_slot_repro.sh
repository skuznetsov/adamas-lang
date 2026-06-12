#!/usr/bin/env bash
# B1c regression (2026-06-11): generic OWNER monomorphized during lowering,
# generic value-struct FIELD type monomorphized even later.
#
# B1a (98cf32ab) closed the pre-lowering stale-slot family by force-
# monomorphizing recorded ref-fallback struct types before the final
# align_all_class_ivars pass. The residual hole: an owner that is itself a
# generic instantiation created only while lowering bodies (LateOwner(Int64))
# misses that fixpoint. Its align_class_ivars consumed
# type_size(MyPair(Int64)) before MyPair(Int64) had class_info -> pointer
# fallback slot=8 for a 16-byte value struct; nothing re-laid the owner out
# (relayout after lowering started is unsound). Ledger signature:
# layout_dep ref_fallback for LateOwner(Int64)#@pair followed by
# layout_dep.stale_owner on MyPair(Int64) registration, no healed row;
# runtime read of @pair returned garbage (CANARY_CLOBBERED code=10).
#
# B1c fix: type_size monomorphizes generic value-struct field types ON
# DEMAND (same candidate filter as the B1a fixpoint, armed only after the
# fixpoint so partial early registrations cannot poison @monomorphized),
# making the owner's FIRST layout correct.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/late_owner_slot.XXXXXX")"
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
struct MyPair(T)
  @a : T
  @b : T

  def initialize(@a : T, @b : T); end

  def sum : T
    @a + @b
  end
end

class LateOwner(T)
  @before : Int64
  @pair : MyPair(T)
  @after : Int64

  def initialize(a : T, b : T)
    @before = 0x1111111111111111_i64
    @pair = MyPair(T).new(a, b)
    @after = 0x2222222222222222_i64
  end

  def check : Int32
    bad = 0
    bad += 1 if @before != 0x1111111111111111_i64
    bad += 1 if @after != 0x2222222222222222_i64
    bad += 10 if @pair.sum != 30_i64
    bad
  end
end

def trigger
  o = LateOwner(Int64).new(10_i64, 20_i64)
  o.check
end

r = trigger
if r == 0
  STDERR.puts "CANARIES_INTACT"
else
  STDERR.puts "CANARY_CLOBBERED code=#{r}"
end
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
stderr_text="$(awk '/^=== STDERR ===/{flag=1;next}/^\[EXIT/{flag=0}flag' "$RUN_OUT" | tr -d '\r')"

echo "compiler: $COMPILER"
echo "tmp_dir: $TMP_DIR"
echo "stderr:"
printf '%s\n' "$stderr_text"

if grep -q 'CANARIES_INTACT' <<<"$stderr_text"; then
  echo "fixed: late-monomorphized owner sizes its generic struct field on demand"
  exit 0
fi

echo "open bug reproduced: lowering-time owner froze pointer-word slot for late generic value-struct field"
exit 1
