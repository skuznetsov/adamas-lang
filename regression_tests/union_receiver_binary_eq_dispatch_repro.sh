#!/usr/bin/env bash
# `==`/`!=` on a union receiver with 2+ non-nil variants (`Int32 | String`,
# `UInt32 | {String, String}`, `Int32 | String | Nil`) must dispatch on the
# runtime variant. A static resolve against the union picked one variant's
# overload (Int32#==, wrong Tuple#== arity), so `ivar == "p"` was always false.
# In S2 this made `narrowing.carrier == {cell_class, cell_name}` never match,
# dropping closure-cell truthy narrowing (S3: bodyless Nil#includes?$String).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/union_receiver_binary_eq_dispatch_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/t.cr" <<'CR'
class IBox
  def initialize(@c : Int32 | String); end
  def c; @c; end
end

alias Carrier = UInt32 | {String, String}
record Nw, name : String, carrier : Carrier

def ivar_eq(b : IBox, a : String) : Bool
  b.c == a
end

def local_eq(b : IBox, a : String) : Bool
  x = b.c
  x == a
end

def param_ne(x : Int32 | String, a : String) : Bool
  y = x
  y = 3 if a == "zzz"
  y != a
end

def int_eq(x : Int32 | String, i : Int32) : Bool
  x == i
end

def nilable_eq(x : Int32 | String | Nil, a : String) : Bool
  x == a
end

def nilable_nil(x : Int32 | String | Nil) : Bool
  x == nil
end

def tuple_carrier(n : Nw, a : String, b : String) : Bool
  n.carrier == {a, b}
end

STDERR.puts "ivar_eq_str=#{ivar_eq(IBox.new("p"), "p")}"
STDERR.puts "ivar_eq_int=#{ivar_eq(IBox.new(1), "p")}"
STDERR.puts "local_eq=#{local_eq(IBox.new("p"), "p")}"
STDERR.puts "param_ne_same=#{param_ne("p", "p")}"
STDERR.puts "param_ne_diff=#{param_ne("q", "p")}"
STDERR.puts "int_eq_int=#{int_eq(5, 5)}"
STDERR.puts "int_eq_str=#{int_eq("5", 5)}"
STDERR.puts "nilable_eq_str=#{nilable_eq("p", "p")}"
STDERR.puts "nilable_eq_nil=#{nilable_eq(nil, "p")}"
STDERR.puts "nilable_nil_nil=#{nilable_nil(nil)}"
STDERR.puts "nilable_nil_int=#{nilable_nil(0)}"
STDERR.puts "tuple_match=#{tuple_carrier(Nw.new("c", {"a", "b"}), "a", "b")}"
STDERR.puts "tuple_miss=#{tuple_carrier(Nw.new("c", {"a", "b"}), "a", "x")}"
STDERR.puts "tuple_vs_u32=#{tuple_carrier(Nw.new("c", 7_u32), "a", "b")}"
STDERR.flush
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/t.cr" -o "$WORK_DIR/t" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/t" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
cat >"$WORK_DIR/expected" <<'OUT'
ivar_eq_str=true
ivar_eq_int=false
local_eq=true
param_ne_same=false
param_ne_diff=true
int_eq_int=true
int_eq_str=false
nilable_eq_str=true
nilable_eq_nil=false
nilable_nil_nil=true
nilable_nil_int=false
tuple_match=true
tuple_miss=false
tuple_vs_u32=false
OUT
grep -oE '^[a-z_0-9]+=(true|false)' "$WORK_DIR/run.log" >"$WORK_DIR/actual" || true
if ! diff -u "$WORK_DIR/expected" "$WORK_DIR/actual" >&2; then
  echo "FAIL: union-receiver ==/!= compared the wrong variant" >&2
  exit 1
fi
echo "PASS: union-receiver ==/!= dispatches on the runtime variant"
