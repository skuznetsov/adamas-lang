#!/usr/bin/env bash
set -euo pipefail

# Ensure-on-early-return regression (2026-07-04, B5 root cause).
#
# HIR lowering used to emit `ensure` bodies only on the CFG fall-through
# path (lower_begin's ensure_block). Early exits — `return` inside
# begin/ensure and inline-return jumps out of inlined yield callees —
# terminated the block directly and SKIPPED the ensure body entirely.
# In the self-hosted compiler this dropped `@arena = old_arena` restores
# (inline_block_return_type_name), leaving @arena pointing at the block's
# arena while lowering the callee def body => garbage node dispatch =>
# lower_super SIGSEGV (B5 frontier, see
# b5_selfhost_each_with_index_inline_yield_repro.sh).
#
# Checks (in one program):
#   A  - `return` inside begin/ensure runs the ensure body
#   B  - normal fall-through still runs ensure exactly once
#   C1,C2 - nested begin/ensure: return runs both, innermost first
#   D  - non-local `return` from a block runs the inlined callee's ensure
#   F5 - a local first assigned INSIDE the begin body stays resolvable
#        in the ensure at an early return (locals overlay, not replacement)
#   E  - the emitted ensure body resolves CALLEE-locals, not the return
#        site's locals: `with_mark { return }` where the helper's ensure is
#        `@mark = old` (old = helper-local). Without the locals snapshot the
#        identifier bound to garbage under caller locals and poisoned the
#        ivar with a stack address (successor-B5 s2 enum-register crash).
#
# Known pre-existing gap tolerated here: code after `yield` may still run
# on the non-local-return path ("D-unreachable" entry). The check asserts
# A,B,C1,C2,D appear as a subsequence, so fixing that gap keeps this green.
#
# Usage: regression_tests/ensure_early_return_repro.sh [compiler]

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"

TMP_DIR="$(mktemp -d /tmp/ensure_early_return.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/probe.cr" <<'CR'
class Probe
  @log : Array(String) = [] of String

  def log : Array(String)
    @log
  end

  def add(s : String)
    @log << s
  end

  def ret_in_ensure : Int32
    begin
      return 1
    ensure
      add("A")
    end
  end

  def normal : Int32
    r = 0
    begin
      r = 2
    ensure
      add("B")
    end
    r
  end

  def nested : Int32
    begin
      begin
        return 3
      ensure
        add("C1")
      end
    ensure
      add("C2")
    end
  end

  def with_yield : Int32
    begin
      yield
      add("D-unreachable")
    ensure
      add("D")
    end
    0
  end

  def nlr : Int32
    with_yield { return 4 }
    5
  end

  @mark : String = "init"

  def mark : String
    @mark
  end

  def with_mark(v : String, &) : Nil
    old = @mark
    @mark = v
    begin
      yield
    ensure
      @mark = old
    end
  end

  def hunt : Int32
    with_mark("inner") do
      return 6
    end
    9
  end

  def begin_local : Int32
    begin
      y = 5
      return 8
    ensure
      add("F#{y}")
    end
  end
end

p = Probe.new
r1 = p.ret_in_ensure
r2 = p.normal
r3 = p.nested
r4 = p.nlr
r5 = p.hunt
r6 = p.begin_local
mark = p.mark
STDERR.puts "RESULT r=#{r1}#{r2}#{r3}#{r4}#{r5}#{r6} mark=#{mark} log=#{p.log.join(",")}"
STDERR.flush
CR

"$COMPILER" "$TMP_DIR/probe.cr" -o "$TMP_DIR/probe_bin" > "$TMP_DIR/compile.log" 2>&1 || {
  echo "FAIL: compile rc=$? (see $TMP_DIR/compile.log)"
  tail -5 "$TMP_DIR/compile.log" || true
  exit 1
}

out="$("$ROOT_DIR/scripts/run_safe.sh" "$TMP_DIR/probe_bin" 5 512 2>&1 | grep "RESULT" || true)"
echo "$out"

if [[ "$out" != *"r=123468"* ]]; then
  echo "FAIL: wrong return values (expect r=123468)"
  exit 1
fi

if [[ "$out" != *"mark=init"* ]]; then
  echo "FAIL: callee-local ensure resolved wrong locals (expect mark=init)"
  exit 1
fi

log="${out##*log=}"
# A,B,C1,C2,D must appear in order (subsequence; extra entries tolerated).
if [[ "$log" != *"A"* || "$log" != *"B"* || "$log" != *"C1"* || "$log" != *"C2"* || "$log" != *"D"* ]]; then
  echo "FAIL: missing ensure entries in log=$log (expect subsequence A,B,C1,C2,D)"
  exit 1
fi

if [[ "$log" != *"F5"* ]]; then
  echo "FAIL: begin-body local lost in ensure at early return (expect F5 in log=$log)"
  exit 1
fi
pos_a="${log%%A*}"; pos_b="${log%%B*}"; pos_c1="${log%%C1*}"; pos_c2="${log%%C2*}"; pos_d="${log%%D*}"
if (( ${#pos_a} > ${#pos_b} || ${#pos_b} > ${#pos_c1} || ${#pos_c1} > ${#pos_c2} || ${#pos_c2} > ${#pos_d} )); then
  echo "FAIL: ensure entries out of order in log=$log (expect A..B..C1..C2..D)"
  exit 1
fi

echo "OK: ensure runs on early returns (A,B,C1,C2,D in order)"
exit 0
