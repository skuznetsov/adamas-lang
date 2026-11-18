#!/usr/bin/env bash
# Regression: an ensure run by an early exit sees the bindings at the exit.
#
# break/next/return out of a begin ran its ensure body against the locals
# snapshot taken when the begin was entered, so the ensure printed stale
# values, and its own assignments never reached the exit edge (a loop break
# after `ensure n = 50` kept the old n). In the scope's own environment the
# ensure now reads the current bindings and its writes flow to the exit. When
# the exit fires from a caller block that the owning def yielded to, the
# ensure reads that def's bindings at the yield, not the caller's.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/early-exit-ensure.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/m.cr" <<'CR'
def a : Int32
  n = 0
  loop do
    begin
      n += 1
      break if n == 3
    ensure
      STDERR.puts "a-e #{n}"
    end
  end
  n
end

def b : Int32
  n = 0
  loop do
    begin
      n += 1
      break
    ensure
      n = 50
    end
  end
  n
end

def c(x : Int32) : Int32
  y = x
  begin
    y += 1
    return y
  ensure
    STDERR.puts "c-e #{y}"
  end
end

def with_c
  begin
    yield
  ensure
    STDERR.puts "wc"
  end
end

def d : Int32
  n = 1
  with_c do
    n = 7
    return n
  end
  0
end

def with_n
  n = 100
  begin
    yield
  ensure
    STDERR.puts "with_n #{n}"
  end
end

def e : Int32
  n = 5
  with_n do
    n = 6
    return n
  end
  0
end

def f : Int32
  n = 0
  i = 0
  while i < 4
    i += 1
    begin
      n += 10
      next if i == 2
      n += 1
    ensure
      STDERR.puts "f-e #{i} #{n}"
    end
  end
  n
end

def g : Int32
  s = 0
  [1, 2, 3].each do |v|
    begin
      s += v
      next if v == 2
    ensure
      STDERR.puts "g-e #{v} #{s}"
    end
  end
  s
end

def inner_ret(k : Int32) : Int32
  m = k
  begin
    m += 5
    return m if m > 6
    m
  ensure
    STDERR.puts "ir-e #{m}"
  end
end

def helper_with(k : Int32)
  m = k * 100
  begin
    m += 1
    yield m
  ensure
    STDERR.puts "hw-e #{m}"
  end
end

def shadow : Int32
  m = 3
  helper_with(2) do |v|
    m = v + m
    break
  end
  m
end

def outer_around : Int32
  z = 1
  begin
    helper_with(4) do |v|
      z = v
      return z
    end
  ensure
    STDERR.puts "oa-e #{z}"
  end
  0
end

def next_update : Int32
  i = 0
  acc = 0
  while i < 5
    begin
      i += 1
      next if i.even?
      acc += i
    ensure
      acc += 100 if i == 2
    end
  end
  acc
end

def deep_inline(x : Int32) : Int32
  r = x
  helper_with(1) do |v|
    helper_with(2) do |w|
      r = r + v + w
      return r
    end
  end
  0
end

STDERR.puts a
STDERR.puts b
STDERR.puts c(1)
STDERR.puts d
STDERR.puts e
STDERR.puts f
STDERR.puts g
STDERR.puts inner_ret(1)
STDERR.puts inner_ret(3)
STDERR.puts shadow
STDERR.puts outer_around
STDERR.puts next_update
STDERR.puts deep_inline(7)
STDERR.puts "done"
CR

expected='a-e 1
a-e 2
a-e 3
3
50
c-e 2
2
wc
7
with_n 100
6
f-e 1 11
f-e 2 21
f-e 3 32
f-e 4 43
43
g-e 1 1
g-e 2 3
g-e 3 6
6
ir-e 6
6
ir-e 8
8
hw-e 201
204
hw-e 401
oa-e 401
401
109
hw-e 201
hw-e 101
309
done'

strip() { grep -v '^\[RUN_SAFE\|^\[EXIT\|^===\|^\[KILL\|run_safe\.sh: ' || true; }

if [[ -n "$CRYSTAL_BIN" ]]; then
  "$CRYSTAL_BIN" build "$WORK_DIR/m.cr" -o "$WORK_DIR/m_oracle" > "$WORK_DIR/oracle.log" 2>&1
  oracle_out="$("$SAFE_RUNNER" "$WORK_DIR/m_oracle" 5 256 2>&1 | strip)"
  if [[ "$oracle_out" != "$expected" ]]; then
    echo "ORACLE_MISMATCH: $oracle_out" >&2
    exit 1
  fi
fi

if ! "$SAFE_RUNNER" "$ADAMAS_BIN" 300 6144 "$WORK_DIR/m.cr" -o "$WORK_DIR/m" > "$WORK_DIR/build.log" 2>&1 || [[ ! -x "$WORK_DIR/m" ]]; then
  echo "FAIL: early-exit ensure program did not compile" >&2
  strip < "$WORK_DIR/build.log" | tail -5 >&2
  exit 1
fi

set +e
out="$("$SAFE_RUNNER" "$WORK_DIR/m" 5 256 2>&1)"
status=$?
set -e
printed="$(printf '%s\n' "$out" | strip)"
if [[ $status -ne 0 || "$printed" != "$expected" ]]; then
  echo "FAIL: early-exit ensure program exit=$status" >&2
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$printed") >&2 || true
  exit 1
fi

echo "PASS: early-exit ensure sees the bindings at the exit"
