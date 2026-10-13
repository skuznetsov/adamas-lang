#!/usr/bin/env bash
# No-prelude raw-yield regression for a literal Nil callback over a real
# Int32|Int64 producer. The ternary keeps the carrier's union tags explicit so
# a producer if-join cannot mask a raw-yield forwarding failure. The callee
# returns a wide Int64 independently of the callback result, and the callback
# records both union tags before returning the literal nil expression. Set
# RAW_NIL_PRODUCER_STYLE=if to exercise the statement-if producer join as a
# separate control, independently of the ternary's explicit union carrier.
#
# The expected process status is 0; the probe exits 81 for a wrong callee
# result and 82 when the callback does not observe Int32 followed by Int64.
# Set EXPECT_RAW_YIELD_NIL_MISMATCH=1 to record only that exact semantic red
# result while a surrounding raw-union fix is still being integrated.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
ORIGINAL_CRYSTAL="${ORIGINAL_CRYSTAL:-crystal}"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/raw_yield_nil_callback.XXXXXX")"

PRODUCER_STYLE="${RAW_NIL_PRODUCER_STYLE:-ternary}"
case "$PRODUCER_STYLE" in
  ternary)
    PRODUCER_SOURCE='  flag ? 7_i32 : 4294967296_i64'
    ;;
  if)
    PRODUCER_SOURCE=$'  if flag\n    7_i32\n  else\n    4294967296_i64\n  end'
    ;;
  *)
    echo "ERROR: RAW_NIL_PRODUCER_STYLE must be ternary or if" >&2
    exit 2
    ;;
esac

cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$WORKDIR"
  else
    rm -rf "$WORKDIR"
  fi
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi
if ! command -v "$ORIGINAL_CRYSTAL" >/dev/null 2>&1; then
  echo "ERROR: original Crystal compiler not found: $ORIGINAL_CRYSTAL" >&2
  exit 2
fi

SRC="$WORKDIR/repro.cr"
ORIGINAL_BIN="$WORKDIR/original.bin"
STAGE_BIN="$WORKDIR/stage.bin"

cat >"$SRC" <<CR
lib LibC
  fun exit(status : Int32) : NoReturn
end

class Counter
  def initialize
    @value = 0
  end

  def mark_int32
    @value = @value * 10 + 1
  end

  def mark_int64
    @value = @value * 10 + 2
  end

  def value : Int32
    @value
  end
end

# Keep the producer genuinely union-shaped at the raw-yield boundary.
def produce(flag : Bool) : Int32 | Int64
$PRODUCER_SOURCE
end

# The callee result is independently Int64. Its callback is untyped, and the
# callback's final literal expression is Nil.
def consume(first : Int32 | Int64, second : Int32 | Int64, &block) : Int64
  yield first
  yield second
  4294967296_i64
end

counter = Counter.new
result = consume(produce(true), produce(false)) do |value|
  if value.is_a?(Int32)
    counter.mark_int32
  else
    counter.mark_int64
  end
  nil
end

LibC.exit(81) unless result == 4294967296_i64
LibC.exit(82) unless counter.value == 12
CR

original_compile_rc=0
CRYSTAL_CACHE_DIR="$WORKDIR/original-cache" "$RUN_SAFE" "$ORIGINAL_CRYSTAL" \
  120 8192 build "$SRC" -o "$ORIGINAL_BIN" \
  >"$WORKDIR/original.compile.log" 2>&1 || original_compile_rc=$?
if [[ "$original_compile_rc" -ne 0 ]]; then
  echo "FAIL: original Crystal could not build raw-yield Nil callback probe" >&2
  tail -40 "$WORKDIR/original.compile.log" >&2
  exit 1
fi

original_run_rc=0
"$RUN_SAFE" "$ORIGINAL_BIN" 5 512 >"$WORKDIR/original.run.log" 2>&1 || original_run_rc=$?
if [[ "$original_run_rc" -ne 0 ]]; then
  echo "FAIL: original Crystal expected raw-yield tag probe status 0, got $original_run_rc" >&2
  cat "$WORKDIR/original.run.log" >&2
  exit 1
fi

stage_compile_rc=0
ADAMAS_DISABLE_INLINE_YIELD=1 DEBUG_RAW_CALLBACK_ABI=1 "$RUN_SAFE" "$COMPILER" \
  120 8192 "$SRC" --no-prelude -o "$STAGE_BIN" \
  >"$WORKDIR/stage.compile.log" 2>&1 || stage_compile_rc=$?
if [[ "$stage_compile_rc" -ne 0 ]]; then
  echo "FAIL: Adamas could not compile raw-yield Nil callback probe" >&2
  tail -40 "$WORKDIR/stage.compile.log" >&2
  exit 1
fi

# The raw callback ABI must reach the callee definition under the exact
# materialized target.  Compare the callback Proc type at the callsite with
# the block formal in the emitted HIR; runtime success alone can miss a
# pointer-shaped callee that happens to accept the same function pointer.
HIR_BASE="$WORKDIR/stage_hir"
hir_compile_rc=0
ADAMAS_DISABLE_INLINE_YIELD=1 DEBUG_RAW_CALLBACK_ABI=1 "$RUN_SAFE" "$COMPILER" \
  120 8192 "$SRC" --no-prelude --emit hir --no-link -o "$HIR_BASE" \
  >"$WORKDIR/stage.hir.compile.log" 2>&1 || hir_compile_rc=$?
if [[ "$hir_compile_rc" -ne 0 || ! -s "$HIR_BASE.hir" ]]; then
  echo "FAIL: Adamas could not emit HIR for raw-yield Nil callback probe" >&2
  tail -40 "$WORKDIR/stage.hir.compile.log" >&2
  exit 1
fi
proc_type_id="$(sed -nE 's/.*func_pointer @__crystal_block_proc_0 : ([0-9]+)$/\1/p' "$HIR_BASE.hir" | head -1)"
formal_type_id="$(sed -nE 's/^func @consume\$Int32 \| Int64_Int32 \| Int64_block\([^,]+, [^,]+, %[^:]+: ([0-9]+) \[block\]\).*/\1/p' "$HIR_BASE.hir" | head -1)"
hir_contract_ok=1
if [[ -z "$proc_type_id" || -z "$formal_type_id" ]]; then
  echo "FAIL: missing callback or callee HIR type" >&2
  exit 1
fi
if [[ "$proc_type_id" != "$formal_type_id" ]]; then
  hir_contract_ok=0
  echo "FAIL: raw callback callee formal lost its Proc type (proc=$proc_type_id formal=$formal_type_id)" >&2
  grep -n -E 'func_pointer @__crystal_block_proc_0|^func @consume\$Int32' "$HIR_BASE.hir" >&2 || true
fi

stage_run_rc=0
ADAMAS_DISABLE_INLINE_YIELD=1 "$RUN_SAFE" "$STAGE_BIN" 5 512 \
  >"$WORKDIR/stage.run.log" 2>&1 || stage_run_rc=$?
if [[ "$stage_run_rc" -eq 0 && "$hir_contract_ok" -eq 1 ]]; then
  echo "PASS: raw-yield Nil callback preserves Int32 and Int64 tags"
  exit 0
fi

echo "raw-yield Nil callback mismatch: original exit 0, Adamas exit $stage_run_rc" >&2
cat "$WORKDIR/stage.compile.log" >&2
cat "$WORKDIR/stage.run.log" >&2
if [[ "${EXPECT_RAW_YIELD_NIL_MISMATCH:-0}" == "1" && "$stage_run_rc" -eq 82 ]]; then
  echo "MEASURED_RED: original exit 0, Adamas exit 82"
  exit 0
fi
exit 1
