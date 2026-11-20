#!/usr/bin/env bash
# Regression: a call with a block selects its overload per union member, as
# a blockless call does.
#
# The blockless union fanout emits one Call per arm, but it declines block
# calls (the block is inlined into the selected body). Block calls were then
# lowered once against the whole union type, so the overload chosen for the
# union ran for every member:
# - `fb(y) { 2 }` with `y = "t"` over `fb(s : String, &)` and
#   `fb(x : T, &) forall T` printed `FT(t:(Int32 | String),2)`, not `FS(t,2)`.
# - `hb(y)` over `hb(x : String, &)` / `hb(x : Int32 | String, &)` ran the
#   union overload for a String.
# - instance calls (`acc.add(y) { ... }`), `@ivar` and call-result arguments
#   took the wrong overload as well.
# - `rt(z) { |k| k }` over `rt(x : Int32, &)` / `rt(x : String, &)` inlined
#   the Int32 body with the union value (`Int32#*` on the union) and the
#   program hung.
# Each arm lowers the call with the argument, evaluated once (`gen.next_val`
# runs once per call), narrowed by its tags; the block body still sees the
# source local with its union type (`typeof(y)` in the block is
# `(Int32 | String)`).
# Overloads that take the whole union (`x : T`, untyped, `x : Int32 | String`)
# still receive the union type; members selecting a restricted overload such
# as `x : Int32 | Nil` share it with their sub-union type.
# Expected output is checked against original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/block-union-dispatch.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/m.cr" <<'CR'
def fb(s : String, &) : String
  "FS(#{s},#{yield})"
end

def fb(x : T, &) : String forall T
  "FT(#{x}:#{typeof(x)},#{yield})"
end

def hb(x : String, &) : String
  "HS(#{x},#{yield})"
end

def hb(x : Int32 | String, &) : String
  "HU(#{x}:#{typeof(x)},#{yield})"
end

def nb(x : Nil, &) : String
  "NN(#{yield 0})"
end

def nb(x : Int32, &) : String
  "NI(#{x},#{yield x})"
end

def tb(s : String, &) : String
  "TS(#{s},#{yield})"
end

def tb(x, &) : String
  "TX(#{x.inspect},#{yield})"
end

def gb(s : String, &) : String
  "GS(#{s},#{yield})"
end

def gb(x : Int32 | Nil, &) : String
  "GN(#{x.inspect}:#{typeof(x)},#{yield})"
end

class Acc
  def initialize(@n : Int32)
  end

  def add(x : Int32, &)
    @n += yield x
  end

  def add(x : String, &)
    @n += yield x.size
  end

  def n
    @n
  end
end

class Holder
  def initialize(@v : Int32 | String)
  end

  def v
    @v
  end

  def via_ivar
    hb(@v) { 0 }
  end
end

class Gen
  @count = 0

  def count
    @count
  end

  def next_val : Int32 | String
    @count += 1
    @count % 2 == 1 ? "o#{@count}" : @count
  end
end

def rt(x : Int32, &)
  yield x
  x * 10
end

def rt(x : String, &)
  yield 0
  "s:#{x}"
end

z = ARGV.size > 5 ? "s" : 2
y = ARGV.size > 5 ? 4 : "t"
w = ARGV.size > 5 ? 3 : nil
v = ARGV.size > 6 ? 1 : (ARGV.size > 5 ? "a" : nil)
STDERR.puts fb(z) { 1 }
STDERR.puts fb(y) { 2 }
STDERR.puts hb(y) { 3 }
STDERR.puts hb(z) { 4 }
STDERR.puts nb(w) { |k| k + 5 }
STDERR.puts tb(v) { 6 }
STDERR.puts gb(v) { 7 }
STDERR.puts gb(y) { 8 }
total = 0
acc = Acc.new(10)
acc.add(y) { |k| total += k; k * 2 }
acc.add(z) { |k| total += k; k * 3 }
STDERR.puts acc.n
STDERR.puts total
STDERR.puts fb(y) { typeof(y).to_s }
STDERR.puts Holder.new("h").via_ivar
STDERR.puts hb(Holder.new(7).v) { 9 }
calls = 0
r = rt(calls > 1 ? y : z) { |k| calls += 1; k }
STDERR.puts "#{r.inspect}:#{typeof(r)}:#{calls}"
[1, 2].each do |i|
  r = rt(i > 1 ? y : z) { |k| calls += k }
end
STDERR.puts calls
gen = Gen.new
STDERR.puts hb(gen.next_val) { gen.count }
STDERR.puts hb(gen.next_val) { gen.count }
STDERR.puts gen.count
CR

expected='FT(2:(Int32 | String),1)
FS(t,2)
HS(t,3)
HU(2:(Int32 | String),4)
NN(5)
TX(nil,6)
GN(nil:(Int32 | Nil),7)
GS(t,8)
18
3
FS(t,(Int32 | String))
HS(h,0)
HU(7:(Int32 | String),9)
20:(Int32 | String):1
3
HS(o1,1)
HU(2:(Int32 | String),2)
2'

strip() { grep -v '^\[RUN_SAFE\|^\[EXIT\|^===\|^\[KILL\|^\[CRASH\|run_safe\.sh: ' || true; }

run_program() {
  local bin="$1"
  set +e
  out="$("$SAFE_RUNNER" "$bin" 5 256 2>&1)"
  status=$?
  set -e
  printed="$(printf '%s\n' "$out" | strip)"
}

if [[ -n "$CRYSTAL_BIN" ]]; then
  "$CRYSTAL_BIN" build "$WORK_DIR/m.cr" -o "$WORK_DIR/m_oracle" > "$WORK_DIR/oracle.log" 2>&1
  run_program "$WORK_DIR/m_oracle"
  if [[ $status -ne 0 || "$printed" != "$expected" ]]; then
    echo "ORACLE_MISMATCH: exit=$status" >&2
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$printed") >&2 || true
    exit 1
  fi
fi

if ! "$SAFE_RUNNER" "$ADAMAS_BIN" 300 6144 "$WORK_DIR/m.cr" -o "$WORK_DIR/m" > "$WORK_DIR/build.log" 2>&1 || [[ ! -x "$WORK_DIR/m" ]]; then
  echo "FAIL: program did not compile" >&2
  strip < "$WORK_DIR/build.log" | grep -i error | head -5 >&2
  exit 1
fi

run_program "$WORK_DIR/m"
if [[ $status -ne 0 || "$printed" != "$expected" ]]; then
  echo "FAIL: exit=$status" >&2
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$printed") >&2 || true
  exit 1
fi

echo "PASS: block calls dispatch union arguments per member"
