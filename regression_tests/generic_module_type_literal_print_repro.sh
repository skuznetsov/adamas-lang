#!/usr/bin/env bash
# Regression: generic module instance literals print their own name.
#
# `Gen(Int32)` for `module Gen(T)` has no ClassInfo; four producers broke it:
#   - lower_generic_type_ref read the literal's TypeRef from ClassInfo and
#     emitted `literal nil : Void`, so the value printed an unrelated name;
#   - the interned instance kept a caller's root-anchored argument spelling
#     (`Gen(::Int32)`), a second type next to `Gen(Int32)`, because only
#     class templates canonicalized nominal generic arguments;
#   - the macro owner for `{{ @type.name }}` looked modules up by exact
#     @module_defs key, which is the declaration `Gen(T)`, so it printed "";
#   - static receivers (`Gen(Int32).name`) built the owner from the anchored
#     argument spelling and folded "Gen(::Int32)".
#
# Not covered: `Gen(Int32) == Gen(Int32)` is false in Crystal (the generic
# module metaclass does not match `Class#==(other : Class)` and lands on
# Value#==); Adamas returns true.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/generic-module-type-literal-print.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/m.cr" <<'CR'
module Mo
end

module Gen(T)
end

module Outer
  module GM(A, B)
  end
end

class Box(T)
end

def show(x)
  STDERR.puts x
end

STDERR.puts Gen(Int32)
STDERR.puts Gen(String)
STDERR.puts Outer::GM(Int32, String)
STDERR.puts Box(Int32)
STDERR.puts Gen(Int32).name
STDERR.puts Outer::GM(Int32, String).name
STDERR.puts Gen(Array(Int32)).name
STDERR.puts Gen(Int32).to_s
STDERR.puts Gen(Int32).inspect
x = Gen(Char)
STDERR.puts x
show(Gen(Bool))
STDERR.puts "#{Mo}|#{Gen(Int32)}!"
STDERR.puts(Gen(Int32) == Gen(String))
STDERR.puts Gen(Outer::GM(Char, Bool))
io = IO::Memory.new
io << Gen(Int32) << "," << Outer::GM(Char, Bool)
STDERR.puts io.to_s
CR

expected='Gen(Int32)
Gen(String)
Outer::GM(Int32, String)
Box(Int32)
Gen(Int32)
Outer::GM(Int32, String)
Gen(Array(Int32))
Gen(Int32)
Gen(Int32)
Gen(Char)
Gen(Bool)
Mo|Gen(Int32)!
false
Gen(Outer::GM(Char, Bool))
Gen(Int32),Outer::GM(Char, Bool)'

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

echo "PASS: generic module instance literals print their own name"
