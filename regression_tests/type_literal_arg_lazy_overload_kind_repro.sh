#!/usr/bin/env bash
# Regression: a type-literal actual never binds an instance-restricted formal
# when an inherited target is materialized lazily.
#
# `STDERR.puts String` failed with "undefined method 'ends_with?' for String"
# (and a user `Sink#take(String)` with "undefined method 'size'"). Virtual
# replay names the per-descendant target by source kind
# (`File#puts$String.class`), but lazy materialization resolved that name's
# Def from ABI TypeRefs only. A type object and an instance share one
# TypeRef, so the exact/suffix lookups picked `puts(string : String)` and
# lowered `string.ends_with?` as a metaclass call. The lookups now carry the
# source kind spelled by the requested suffix.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/type-literal-lazy-overload.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/m.cr" <<'CR'
module Gen(T)
  def self.kind
    T
  end
end

abstract class Sink
  abstract def name : String

  def take(x : String)
    "#{name}:str:#{x.size}"
  end

  def take(x)
    "#{name}:any:#{x}"
  end
end

class SinkA < Sink
  def name : String
    "a"
  end
end

class SinkB < Sink
  def name : String
    "b"
  end
end

STDERR.puts String
STDERR.puts Int32
STDERR.puts Array(Int32)
STDERR.puts Gen(String).kind
STDERR.puts "plain"
io = IO::Memory.new
io.puts Char
io.puts "x"
STDERR.print io.to_s
sinks = [SinkA.new, SinkB.new] of Sink
sinks.each do |s|
  STDERR.puts s.take(String)
  STDERR.puts s.take("abc")
  STDERR.puts s.take(7)
end
STDERR.puts SinkA.new.take(String)
CR

expected='String
Int32
Array(Int32)
String
plain
Char
x
a:any:String
a:str:3
a:any:7
b:any:String
b:str:3
b:any:7
a:any:String'

strip() { grep -v '^\[RUN_SAFE\|^\[EXIT\|^===\|^\[KILL\|^\[CRASH' || true; }

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

echo "PASS: type-literal actuals keep their kind in lazy overload lookup"
