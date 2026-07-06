#!/usr/bin/env bash
# Regression test for the while+`next`+Proc#call loop back-edge counter drop
# (the s2 self-host floor "layer 4" LLVM-emission memory runaway root).
#
# Before fix: hir_to_mir @block_map maps a HIR block only to the FIRST MIR
# block of its lowering. When instruction lowering splits the HIR block into a
# subgraph — the Proc#call closure/bare diamond (entry -> bare|closure -> merge)
# — the lowered terminator (and thus the loop back-edge) lives in the MERGE
# block, but resolve_pending_phis keyed the phi incoming with the ENTRY block.
# The LLVM layer then validated real CFG predecessors, found no incoming value
# for the merge block, classified it missing, and defaulted it to 0: the loop
# counter reset to its init value on every pass through the proc-call path.
# In the self-hosted compiler this made LLVMIRGenerator#emit_phi (union branch,
# `block_name.call` proc in the loop) spin forever, allocating interpolated
# strings at ~700MB/s -> s2 LLVM-emission OOM (>16GB), forked workers dying.
#
# Fix: record @block_end_map (HIR block -> FINAL MIR block, captured after
# lower_terminator) and use it in resolve_pending_phis for phi incoming keys
# (also places phi-incoming union_wraps in the correct predecessor block).
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/while_next_proc.XXXXXX")"
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
class Gen
  def lookup(val : UInt32) : String?
    val == 7_u32 ? "%w" : nil
  end

  # c1: minimal — bare `next` + proc call after it in the loop body.
  # Pre-fix: back-edge through the proc-call merge block reset idx to 0 (spin).
  def run_min(vals : Array(UInt32)) : Int32
    block_name = ->(b : UInt32) { "x" }
    incoming = [] of String
    idx = 0
    while idx < vals.size
      val = vals.unsafe_fetch(idx)
      idx += 1
      if val == 7_u32
        next
      end
      incoming << block_name.call(val)
    end
    incoming.size
  end

  # c2: emit_phi union-branch shape — if-let + interpolated push + `next`,
  # proc call with interpolation in BOTH paths.
  def run_phi_shape(vals : Array(UInt32)) : Int32
    block_name = ->(b : UInt32) { "bb#{b}" }
    incoming = [] of String
    idx = 0
    while idx < vals.size
      val = vals.unsafe_fetch(idx)
      idx += 1
      if pred_ref = lookup(val)
        incoming << "[#{pred_ref}, %#{block_name.call(val)}]"
        next
      end
      incoming << "[zero, %#{block_name.call(val)}]"
    end
    incoming.size
  end
end

g = Gen.new
c1 = g.run_min([1_u32, 7_u32, 3_u32])
c2 = g.run_phi_shape([1_u32, 7_u32, 3_u32])
STDERR.puts "c1=#{c1} c2=#{c2}"
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

# Pre-fix this spins allocating ~700MB/s; run_safe kills it on the 256MB cap.
./scripts/run_safe.sh "$BIN" 5 256 >"$RUN_OUT" || true
stderr_text="$(awk '/^=== STDERR ===/{flag=1;next}/^\[EXIT/{flag=0}flag' "$RUN_OUT" | tr -d '\r' | sed '/^$/d')"

echo "compiler: $COMPILER"
echo "tmp_dir: $TMP_DIR"
echo "stderr:"
printf '%s\n' "$stderr_text"

# c1: 3 elements, val==7 skipped -> 2 pushes
# c2: same shape, 7 goes through the if-let(next) push -> 3 pushes total
expected="c1=2 c2=3"

if [[ "$stderr_text" == "$expected" ]]; then
  echo "fixed: while+next+Proc#call back-edge carries the incremented counter"
  exit 0
fi

echo "unexpected output (expected: $expected)"
cat "$RUN_OUT"
exit 1
