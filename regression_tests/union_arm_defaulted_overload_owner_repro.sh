#!/usr/bin/env bash
# Regression: a bare call on a union arm binds the nearest owner's defaulted
# overload, not a farther nilary ancestor def.
#
# Typed or defaulted overloads such as `Int#to_s(base : Int = 10, *, ...)`
# are registered only under mangled keys. The inherited nilary lookup for a
# bare `Int32#to_s` checked just the unmangled `Int#to_s` key, skipped Int,
# and bound `Object#to_s`, whose `to_s(io)` call resolved back to the same
# body: `(Int32 | String)#to_s` on the Int32 arm recursed until it trapped.
# The same skip printed "base" for an abstract parent's defaulted override.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/union-arm-defaulted.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/m.cr" <<'CR'
abstract struct Base
  def describe
    "base"
  end
end

struct Leaf < Base
  def describe(prefix : String = "leaf", *, size : Int32 = 2)
    "#{prefix}#{size}"
  end
end

abstract struct Mid < Base
end

struct Deep < Mid
end

abstract struct Mid2 < Base
  def describe(prefix : String = "mid", *, size : Int32 = 3)
    "#{prefix}#{size}"
  end
end

struct Deep2 < Mid2
end

i = ARGV.size
u = i == 0 ? Leaf.new : Deep.new
STDERR.puts u.describe
w = i == 0 ? Deep2.new : Deep.new
STDERR.puts w.describe
w2 = i == 0 ? Deep.new : Deep2.new
STDERR.puts w2.describe
v = i == 0 ? 7 : "s"
STDERR.puts v.to_s
STDERR.puts "after"
n = i == 0 ? -42_i64 : :sym
STDERR.puts n.to_s
STDERR.puts "n=#{n}"
f = [3, "x", :k][i]
STDERR.puts f.to_s
CR

expected='leaf2
mid3
base
7
after
-42
n=-42
3'

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

echo "PASS: union arm bare calls bind the nearest defaulted overload"
