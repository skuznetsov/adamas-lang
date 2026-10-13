#!/usr/bin/env bash
# A Tuple argument is passed as a borrowed pointer into the caller's stack
# frame. When it was wrapped into a union (`UInt32 | {String, String}`) and
# stored in an ivar, emit_union_wrap stored that borrowed pointer directly in
# the union payload (the Tuple detection indexed the type registry's variant
# list with a descriptor-local id, so it never matched), leaving the record
# with a dangling payload. In S2 this corrupted
# ScopedReceiverNarrowing#carrier and take_closure_cell_narrowing crashed in
# String#==. The payload must own a copy of the tuple.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/union_ivar_borrowed_tuple_payload_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/t.cr" <<'CR'
alias Carrier = UInt32 | {String, String}
record Nw, name : String, value_id : UInt32, carrier : Carrier
record Tw, carrier : {String, String}

def show(tag, cr : Carrier)
  if cr.is_a?(Tuple)
    STDERR.puts "#{tag}=#{cr[0]}|#{cr[1]}"
  else
    STDERR.puts "#{tag}=u32 #{cr}"
  end
end

def clobber(n : Int32) : Int32
  a = {n, n + 1, n + 2, n + 3}
  b = {n * 2, n * 3, n * 4, n * 5}
  a[0] + a[3] + b[1] + b[2]
end

def mk_u(a : String, b : String) : Carrier
  {a, b}
end

def mk_t(a : String, b : String)
  Tw.new({a, b})
end

def mk_n(a : String, b : String)
  Nw.new("x", 5_u32, {a, b})
end

def mk_n2(a : String, b : String)
  t = {a, b}
  n = Nw.new("x", 5_u32, t)
  n
end

def mk_c
  Nw.new("x", 5_u32, {"C", "cell"})
end

show "u", mk_u("C", "cell")
show "t", mk_t("C", "cell").carrier
n = mk_n("C", "cell")
clobber(7)
show "n", n.carrier
n2 = mk_n2("C", "cell")
clobber(9)
show "n2", n2.carrier
c = mk_c
clobber(11)
show "c", c.carrier
STDERR.puts "eq=#{c.carrier == {"C", "cell"}}"
STDERR.flush
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/t.cr" -o "$WORK_DIR/t" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/t" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
cat >"$WORK_DIR/expected" <<'OUT'
u=C|cell
t=C|cell
n=C|cell
n2=C|cell
c=C|cell
eq=true
OUT
grep -aE '^(u|t|n|n2|c|eq)=' "$WORK_DIR/run.log" >"$WORK_DIR/actual" || true
if ! diff -u "$WORK_DIR/expected" "$WORK_DIR/actual" >&2; then
  echo "FAIL: union payload kept a borrowed tuple pointer" >&2
  exit 1
fi
echo "PASS: union payload owns its tuple copy"
