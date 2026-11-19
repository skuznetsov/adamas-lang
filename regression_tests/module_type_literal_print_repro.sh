#!/usr/bin/env bash
# Regression: module type literals print their own name.
#
# In Crystal a module's metaclass inherits Class, so `Mo.to_s(io)`,
# `Mo.name` and `Mo == Other` instantiate Class methods with `@type` = Mo.
# Two producers broke that:
#   - the meta owner for module literals was "Module", which declares no
#     `to_s(io)`, so the call fell through to Object#to_s on the zero literal
#     carrier and printed an empty line;
#   - with owner "Class", the type-literal rewrite still skipped the per-type
#     meta wrapper for modules, so the shared `Class#to_s` body printed "Class".
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/module-type-literal-print.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/m.cr" <<'CR'
module Mo
end

module Own
  def self.to_s(io : IO) : Nil
    io << "custom-own"
  end
end

module Outer
  module Inner
  end
end

module Ext
  extend self

  def greet
    "hi"
  end
end

module Named
  def self.name : String
    "renamed"
  end
end

class Cls
end

def show(x)
  STDERR.puts x
end

STDERR.puts Mo
STDERR.puts Own
STDERR.puts Outer::Inner
STDERR.puts Cls
STDERR.puts Mo.name
STDERR.puts Mo.to_s
STDERR.puts(Mo == Mo)
STDERR.puts(Mo == Outer::Inner)
io = IO::Memory.new
io << Mo << "," << Outer::Inner
STDERR.puts io.to_s
show(Mo)
show(Cls)
STDERR.puts Ext.greet
STDERR.puts Ext
STDERR.puts Named.name
x = Outer::Inner
STDERR.puts x
STDERR.puts "#{Mo}/#{Ext}"
CR

expected='Mo
custom-own
Outer::Inner
Cls
Mo
Mo
true
false
Mo,Outer::Inner
Mo
Cls
hi
Ext
renamed
Outer::Inner
Mo/Ext'

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

echo "PASS: module type literals print their own name"
