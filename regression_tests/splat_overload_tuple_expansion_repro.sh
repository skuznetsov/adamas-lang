#!/usr/bin/env bash
# Regression: `*` calls select overloads like Crystal and keep the packed
# splat body distinct from a one-parameter sibling.
#
# Three faults shared one family:
# - `f *t` over a Tuple is expanded at compile time, so overloads are chosen
#   by the expanded positional actuals. Keeping the splat flag made the
#   resolver prefer any `*args` overload: `puts *objects` with an empty tuple
#   printed `{}` instead of a bare newline, and `g(*Tuple.new)` hit
#   `g(*xs)` instead of `g`.
# - After packing `g(1, 2)` into `g(*xs)`, later lookups saw one Tuple
#   actual without the splat flag and rebound it to `g(x)`.
# - The per-arity packed body was named `hh$Tuple(Int32, Int32)` without the
#   packed-splat marker, the same symbol a one-parameter `hh(x)` gets for a
#   Tuple argument; callsite specialization and virtual replay then
#   materialized the sibling (`STDERR.print 1, "\n"` printed `{1, "\n"}`).
# - A Tuple-typed positional actual was treated as an already-packed splat:
#   `only({1, 2, 3})` ran the body specialized for `only(1, 2, 3)` and
#   `STDERR.print({1, 2}, "\n")` printed `12`. `Object#in?`'s
#   `in?(values)` now reaches `in?(collection)` through the non-splat check.
# - The packed body is callsite-specialized, so its bare family alias must not
#   be lowered as well (`xs[0]` over `Tuple()` failed to compile).
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/splat-overload-tuple.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/m.cr" <<'CR'
class K
  def g : String
    "zero"
  end

  def g(x) : String
    "one(#{x})"
  end

  def g(*xs : _) : String
    "many(#{xs.size})"
  end
end

def hh
  "hzero"
end

def hh(*xs)
  "hmany(#{xs.size})"
end

def hh(x)
  "hone(#{x})"
end

def kk(a, *xs)
  "k(#{a},#{xs.size})"
end

def kk(a)
  "k1(#{a})"
end

def fw(*objects)
  K.new.g *objects
end

def fh(*objects)
  hh *objects
end

def fk(*objects)
  kk *objects
end

def show(*objects)
  STDERR.print "["
  STDERR.puts *objects
  STDERR.print "]\n"
end

def only(*xs)
  "only(#{xs.size}:#{xs[0].size})"
end

def fo(*objects)
  only *objects
end

class T
  def t(x) : String
    "t_one(#{x.size})"
  end

  def t(*xs : _) : String
    "t_many(#{xs.size})"
  end
end

def ft(*objects)
  T.new.t *objects
end

def tz(*xs)
  "tz_many(#{xs.size})"
end

def tz(x)
  "tz_one(#{x.size})"
end

STDERR.puts K.new.g(1, 2)
STDERR.puts K.new.g(1, 2, 3)
STDERR.puts fw
STDERR.puts fw(1)
STDERR.puts fw(1, 2)
STDERR.puts fw(1, "a", 'c')
STDERR.puts fh
STDERR.puts fh(5)
STDERR.puts fh(5, 6)
STDERR.puts hh(5, 6)
STDERR.puts fk(1)
STDERR.puts fk(1, 2, 3)
t = {4, 5}
STDERR.puts K.new.g(*t)
STDERR.puts hh(*t)
STDERR.puts kk(*t)
e = Tuple.new
STDERR.puts K.new.g(*e)
show
show 7
STDERR.print 1, "\n"
STDERR.print 1, "|", 'c', "\n"
STDERR.puts 1, 2
STDERR.puts only({1, 2, 3})
STDERR.puts only({1, 2}, 3)
STDERR.puts fo({1, 2, 3})
STDERR.puts T.new.t({1, 2})
STDERR.puts ft({1, 2})
STDERR.puts ft({1, 2}, 3)
STDERR.puts tz({7, 8, 9})
STDERR.puts tz({7, 8, 9}, 1)
STDERR.puts 5.in?(1, 5)
STDERR.puts 5.in?({1, 2})
STDERR.puts "x".in?({"x", "y"})
STDERR.print({1, 2}, "\n")
STDERR.print "a", {3, 4}, "b", "\n"
CR

expected='many(2)
many(3)
zero
one(1)
many(2)
many(3)
hzero
hone(5)
hmany(2)
hmany(2)
k1(1)
k(1,2)
many(2)
hmany(2)
k(4,1)
zero
[
]
[7
]
1
1|c
1
2
only(1:3)
only(2:2)
only(1:3)
t_one(2)
t_one(2)
t_many(2)
tz_one(3)
tz_many(2)
true
false
true
{1, 2}
a{3, 4}b'

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

echo "PASS: splat calls select Crystal overloads and keep packed bodies distinct"
