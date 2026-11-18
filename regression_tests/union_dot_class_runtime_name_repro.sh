#!/usr/bin/env bash
# Regression: `.class` of a union value names its active variant.
#
# The `.class` lowering read the runtime class only for virtual class
# receivers. A union receiver got the static union type, so `x.class` printed
# "Nil | String" (or the single non-Nil member, "String", for a nil value) and
# `[7, "s"][i].class` printed the whole union. The union descriptor now selects
# the active variant; a virtual class variant reads its object header.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/union-dot-class.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/m.cr" <<'CR'
class Animal; end
class Dog < Animal; end
class Cat < Animal; end
struct Pt
  def initialize(@x : Int32); end
end

i = ARGV.size
a = [nil, "n"]
STDERR.puts a[i].class
STDERR.puts a[i + 1].class
b = [7, "s", :k, 1.5]
STDERR.puts b[i].class
STDERR.puts b[i + 1].class
STDERR.puts b[i + 2].class.name
STDERR.puts "c=#{b[i + 3].class}"
n = i == 0 ? nil : 5
STDERR.puts n.class
p = i == 0 ? [Dog.new, Cat.new][1] : nil
STDERR.puts p.class
d = i == 0 ? Dog.new : "s"
STDERR.puts d.class
e = i == 0 ? Pt.new(1) : nil
STDERR.puts e.class
STDERR.puts typeof(b[i])
CR

expected='Nil
String
Int32
String
Symbol
c=Float64
Nil
Cat
Dog
Pt
(Float64 | Int32 | String | Symbol)'

strip() { grep -v '^\[RUN_SAFE\|^\[EXIT\|^===\|^\[KILL\|^\[CRASH' || true; }

if [[ -n "$CRYSTAL_BIN" ]]; then
  "$CRYSTAL_BIN" build "$WORK_DIR/m.cr" -o "$WORK_DIR/m_oracle" > "$WORK_DIR/oracle.log" 2>&1
  oracle_out="$("$SAFE_RUNNER" "$WORK_DIR/m_oracle" 5 256 2>&1 | strip)"
  if [[ "$oracle_out" != "$expected" ]]; then
    echo "ORACLE_MISMATCH: $oracle_out" >&2
    exit 1
  fi
fi

if ! "$SAFE_RUNNER" "$ADAMAS_BIN" 300 6144 "$WORK_DIR/m.cr" -o "$WORK_DIR/m" > "$WORK_DIR/build.log" 2>&1 || [[ ! -x "$WORK_DIR/m" ]]; then
  echo "FAIL: program did not compile" >&2
  strip < "$WORK_DIR/build.log" | grep -i error | head -5 >&2
  exit 1
fi

set +e
out="$("$SAFE_RUNNER" "$WORK_DIR/m" 5 256 2>&1)"
status=$?
set -e
printed="$(printf '%s\n' "$out" | strip)"
if [[ $status -ne 0 || "$printed" != "$expected" ]]; then
  echo "FAIL: exit=$status" >&2
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$printed") >&2 || true
  exit 1
fi

echo "PASS: union .class names the active variant"
