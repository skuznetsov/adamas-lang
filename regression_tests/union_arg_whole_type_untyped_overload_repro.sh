#!/usr/bin/env bash
# Regression: a union argument that reaches an unrestricted parameter
# (`obj`, `obj : _`) or a bare free variable (`x : T` with `forall T`)
# instantiates that overload with the whole union, as in Crystal.
#
# For `puts(string : String)` and `puts(obj : _)` called with
# `Int32 | String`, the union-argument dispatch sent the Int32 arm to the
# resolver's family alias `IO#puts$arity1`. That body had been lowered for the
# first call shape that demanded it, here `STDERR.puts "abcd"`, so the Int32
# was passed to a String parameter and the program hung. Called the other way
# round it happened to work. Crystal instead calls the overload instantiated
# with `obj : Int32 | String` and passes the union value, so `typeof(obj)` is
# the union on every arm. Expected output is checked against original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/union-arg-whole-type.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/m.cr" <<'CR'
class Sink
  def put(s : String) : String
    "S(#{s})"
  end

  def put(obj) : String
    "O(#{obj}:#{typeof(obj)})"
  end

  def any(s : String) : String
    "AS(#{s})"
  end

  def any(obj : _) : String
    "AO(#{obj}:#{typeof(obj)})"
  end

  def pair(tag : Symbol, obj : String) : String
    "#{tag}=str:#{obj}"
  end

  def pair(tag : Symbol, obj) : String
    "#{tag}=#{obj}:#{typeof(obj)}"
  end

  def num(n : Int32) : String
    "N(#{n})"
  end

  def num(obj) : String
    "NO(#{obj}:#{typeof(obj)})"
  end
end

sink = Sink.new
STDERR.puts "abcd"
STDERR.puts sink.put("first")
STDERR.puts sink.put(1.5)
STDERR.puts sink.any(2_i64)
STDERR.puts sink.pair(:a, 3.5)
z = ARGV.size > 5 ? "s" : 2
STDERR.puts z
STDERR.puts sink.put(z)
STDERR.puts sink.any(z)
STDERR.puts sink.pair(:b, z)
y = ARGV.size > 5 ? 4 : "t"
STDERR.puts y
STDERR.puts sink.put(y)
STDERR.puts sink.pair(:c, y)
STDERR.puts sink.num(z)
STDERR.puts sink.num(y)
w = ARGV.size > 5 ? 'c' : 7_i64
STDERR.puts w
STDERR.puts sink.put(w)

def fv(s : String) : String
  "FS(#{s})"
end

def fv(x : T) : String forall T
  "FT(#{x}:#{typeof(x)})"
end

def dd(s : String, k = 1) : String
  "DS(#{s},#{k})"
end

def dd(x, k = 2) : String
  "DX(#{x}:#{typeof(x)},#{k})"
end

STDERR.puts fv(z)
STDERR.puts dd(z)
CR

expected='abcd
S(first)
O(1.5:Float64)
AO(2:Int64)
a=3.5:Float64
2
O(2:(Int32 | String))
AO(2:(Int32 | String))
b=2:(Int32 | String)
t
S(t)
c=str:t
N(2)
NO(t:(Int32 | String))
7
O(7:(Char | Int64))
FT(2:(Int32 | String))
DX(2:(Int32 | String),2)'
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

echo "PASS: a union argument instantiates whole-type parameters with the union"
