#!/usr/bin/env bash
# Intrinsic block loops (each/times/upto/range/hash/each_with_index/each_char)
# typed the loop phi of an outer local only from its pre-loop type, so
# `ann = nil; ps.each { |p| ann = p }` folded `ann` to Nil after the loop
# (S2 lost `param_annotation` and S3 failed on a bodyless ExprIdBuffer#<< target).
# Also covers Char arithmetic in body inference (`'a' + i` is Char, not Int).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/intrinsic_loop_phi_widen_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/t.cr" <<'CR'
def t_each(ps : Array(String))
  ann = nil
  ps.each { |p| ann = p }
  if ta = ann
    "each=#{ta}"
  else
    "each=nil"
  end
end

def t_each_int(ps : Array(String))
  ann = 0
  ps.each { |p| ann = p }
  "eachi=#{ann}"
end

def t_times
  v = nil
  3.times { |i| v = i * 10 }
  "times=#{v.inspect}"
end

def t_upto
  v = nil
  1.upto(4) { |i| v = "u#{i}" }
  "upto=#{v.inspect}"
end

def t_range
  v = nil
  (0...3).each { |i| v = 'a' + i }
  "range=#{v.inspect}"
end

def t_hash(h : Hash(String, Int32))
  k = nil
  h.each { |kk, vv| k = kk if vv > 1 }
  "hash=#{k.inspect}"
end

def t_ewi(ps : Array(String))
  hit = nil
  ps.each_with_index { |p, i| hit = p if i == 1 }
  "ewi=#{hit.inspect}"
end

def t_chars(s : String)
  last = nil
  s.each_char { |c| last = c }
  "chars=#{last.inspect}"
end

def t_break(ps : Array(String))
  found = nil
  ps.each do |p|
    if p.size > 1
      found = p
      break
    end
  end
  "break=#{found.inspect}"
end

def t_empty(ps : Array(String))
  ann = nil
  ps.each { |p| ann = p }
  "empty=#{ann.inspect}"
end

STDERR.puts t_each(["IdN"])
STDERR.puts t_each_int(["IdN"])
STDERR.puts t_times
STDERR.puts t_upto
STDERR.puts t_range
STDERR.puts t_hash({"a" => 1, "b" => 2})
STDERR.puts t_ewi(["x", "y", "z"])
STDERR.puts t_chars("abc")
STDERR.puts t_break(["a", "bb", "ccc"])
STDERR.puts t_empty([] of String)
STDERR.flush
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/t.cr" -o "$WORK_DIR/t" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/t" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
cat >"$WORK_DIR/expected" <<'OUT'
each=IdN
eachi=IdN
times=20
upto="u4"
range='c'
hash="b"
ewi="y"
chars='c'
break="bb"
empty=nil
OUT
grep -E '^[a-z]+=' "$WORK_DIR/run.log" >"$WORK_DIR/actual" || true
if ! diff -u "$WORK_DIR/expected" "$WORK_DIR/actual" >&2; then
  echo "FAIL: intrinsic loop phis widen outer locals assigned in the block" >&2
  exit 1
fi
echo "PASS: intrinsic loop phis widen outer locals assigned in the block"
