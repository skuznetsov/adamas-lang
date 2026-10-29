#!/usr/bin/env bash
# A local captured by a proc literal lives in a box, and every read of it loads
# the box, typed with the declared (nilable) payload. A `return nil unless
# arena` guard rebound only the SSA value, so after the guard `src(arena)` still
# saw `Nil | AstArena | ...` ("no overload matches source_for_arena" in
# AstToHir#macro_block_value_for, then slice_source_for_expr_in_arena inside
# a `source.try { }` block, while building stage 2).
# A box that only its defining assignment writes (no closure body or second
# assignment, no `pointerof`) is call-stable: a truthy guard now binds the
# local to a narrowed load of the box, and reads use that binding while the
# local machinery keeps it (branch arms, joins, inlined blocks, thunks, loops).
# A proc literal created under that binding reads the box narrowed when the
# box's write is in no loop or block body, so it ran before the proc existed.
# A closure that writes the local keeps it un-narrowed, as in original Crystal.
# Expected output is checked against original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/proc-captured-guard-narrowing.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

CASES=()

# add_case name expected-stderr-lines(|-separated) body
add_case() {
  CASES+=("$1")
  printf '%s\n' "$2" | tr '|' '\n' > "$WORK_DIR/$1.want"
  printf '%s\nexit 0\n' "$3" > "$WORK_DIR/$1.cr"
}

COMMON='
class A
  def initialize(@n : Int32); end
  def size : Int32; @n; end
end

def get(k : Int32) : A?
  k > 0 ? A.new(k) : nil
end

def src(a : A) : Int32
  a.size
end
'

add_case or_guard_after_unless '2|0|1|6' "$COMMON"'
def m(k : Int32) : Int32
  arena = get(k)
  return 0 unless arena
  return 1 if k < 0 || k > arena.size
  s = src(arena)
  pr = -> { arena.size }
  s + pr.call
end

STDERR.puts m(1)
STDERR.puts m(0)
STDERR.puts m(2) == 4 ? 1 : 0
STDERR.puts m(3)'

add_case union_alias_arena '"3nb4"|nil|"5nb6"|nil' '
struct EId
  getter index : Int32
  def initialize(@index : Int32); end
  def invalid?; @index < 0; end
end
class NA; end
class NB; getter v = "nb"; end
alias TN = NA | NB
class A
  def size; 3; end
  def [](i : EId) : TN; i.index > 0 ? NB.new : NA.new; end
end
class B
  def size; 5; end
  def [](i : EId) : TN; NB.new; end
end
class C
  def size; 7; end
  def [](i : EId) : TN; NA.new; end
end
alias AL = A | B | C

class H
  @main = [] of AL
  def initialize(@arena : AL); @main << B.new; end
  def arena_for?(e : EId) : AL?
    return nil if e.index < 0
    return @arena if e.index < @arena.size
    best = nil
    @main.each { |c| best = c if e.index < c.size }
    best
  end
  def src(a : AL) : String?
    a.size.to_s
  end
  def m(e : EId) : String?
    return nil if e.invalid?
    arena = arena_for?(e)
    return nil unless arena
    return nil if e.index < 0 || e.index >= arena.size
    node = arena[e]
    return nil unless node.is_a?(NB)

    source = src(arena)
    bs = source.try { |t| t + node.v } || ""
    pr = ->(x : Int32) : Int32 { x + arena.size }
    bs + pr.call(1).to_s
  end
end

STDERR.puts H.new(A.new).m(EId.new(1)).inspect
STDERR.puts H.new(C.new).m(EId.new(1)).inspect
STDERR.puts H.new(A.new).m(EId.new(4)).inspect
STDERR.puts H.new(A.new).m(EId.new(9)).inspect'

add_case arm_and_chain_merges '3 3 3|0 nil -1|5 5 5|nil u-nil -1|big 200 200|small|3 3|none' "$COMMON"'
def arm_only(k : Int32) : String
  a = get(k)
  pr = -> { a.try(&.size) || -1 }
  x = 0
  if a
    x = src(a)
  end
  "#{x} #{a.try(&.size).inspect} #{pr.call}"
end

def chain(k : Int32) : String
  a = get(k)
  pr = -> { a.try(&.size) || -1 }
  r = if k > 100
        "big"
      elsif a
        src(a).to_s
      else
        "nil"
      end
  s = unless a
        "u-nil"
      else
        src(a).to_s
      end
  "#{r} #{s} #{pr.call}"
end

def nested_sc(k : Int32) : String
  a = get(k)
  return "none" unless a
  return "small" if (k < 0 && a.size > 0) || a.size < 2 || k > 99
  pr = -> { a.size }
  "#{src(a)} #{pr.call}"
end

STDERR.puts arm_only(3)
STDERR.puts arm_only(0)
STDERR.puts chain(5)
STDERR.puts chain(0)
STDERR.puts chain(200)
STDERR.puts nested_sc(1)
STDERR.puts nested_sc(3)
STDERR.puts nested_sc(0)'

add_case owner_writes_reach_box '7 2 2|4 nil -1|10 -1|0 -1' "$COMMON"'
def wy(c : Bool, &)
  return yield if c
  yield
end

def parent_write(k : Int32) : String
  a = get(k)
  return "none" unless a
  pr = -> { a.try(&.size) || -1 }
  first = a.try(&.size)
  a = get(k - 5)
  "#{first} #{a.try(&.size).inspect} #{pr.call}"
end

def thunk_write(k : Int32) : String
  a = get(k)
  pr = -> { a.try(&.size) || -1 }
  return "none" unless a
  before = a.try(&.size)
  wy(true) { a = get(0) }
  "#{before} #{a.try(&.size).inspect} #{pr.call}"
end

def loop_write(k : Int32) : String
  a = get(k)
  pr = -> { a.try(&.size) || -1 }
  total = 0
  while a
    total += a.try(&.size) || 0
    a = get((a.try(&.size) || 1) - 1)
  end
  "#{total} #{pr.call}"
end

STDERR.puts parent_write(7)
STDERR.puts thunk_write(4)
STDERR.puts loop_write(4)
STDERR.puts loop_write(0)'

add_case reads_inside_blocks 's3 3| 1|none|t2 2|12,22 2|-1,-1,1,2,2|nil -1|x1|2 2' "$COMMON"'
def name_for(a : A) : String?
  a.size > 1 ? "s" : nil
end

def src2(a : A, t : String) : String
  "#{t}#{a.size}"
end

def wy(c : Bool, &)
  return yield if c
  yield
end

def m(k : Int32) : String
  arena = get(k)
  return "none" unless arena
  source = name_for(arena)
  bs = source.try { |text| src2(arena, text) } || ""
  pr = -> { arena.size }
  "#{bs} #{pr.call}"
end

def thunk(k : Int32) : String
  arena = get(k)
  return "none" unless arena
  r = wy(true) { src2(arena, "t") }
  pr = -> { arena.size }
  "#{r} #{pr.call}"
end

def mapped(k : Int32) : String
  arena = get(k)
  return "none" unless arena
  r = [1, 2].map { |i| src2(arena, i.to_s) }.join(",")
  pr = -> { arena.size }
  "#{r} #{pr.call}"
end

def per_iteration(n : Int32) : String
  acc = [] of Int32
  n.times do |j|
    a = get(j - 1)
    pr = -> { a.try(&.size) || -1 }
    if a && a.size > 1
      acc << src(a)
    end
    acc << pr.call
  end
  acc.join(",")
end

def guard_in_block(xs : Array(Int32), k : Int32) : String
  a = get(k)
  pr = -> { a.try(&.size) || -1 }
  xs.each { |x| return "x#{x}" unless a }
  "#{a.try(&.size).inspect} #{pr.call}"
end

STDERR.puts m(3)
STDERR.puts m(1)
STDERR.puts m(0)
STDERR.puts thunk(2)
STDERR.puts mapped(2)
STDERR.puts per_iteration(4)
STDERR.puts guard_in_block([] of Int32, 0)
STDERR.puts guard_in_block([1], 0)
STDERR.puts guard_in_block([1], 2)'

add_case proc_created_after_guard '21 22|none|31,32|40 4|none' "$COMMON"'
def after_guard(k : Int32) : String
  arena = get(k)
  return "none" unless arena
  pr = ->(x : Int32) { src(arena) * 10 + x }
  "#{pr.call(1)} #{pr.call(2)}"
end

def nested(k : Int32) : String
  arena = get(k)
  return "none" unless arena
  pr = -> { [1, 2].map { |i| src(arena) * 10 + i }.join(",") }
  pr.call
end

def before_guard(k : Int32) : String
  arena = get(k)
  pr = -> { arena.try(&.size) || -1 }
  return "none" unless arena
  "#{src(arena) * 10} #{pr.call}"
end

STDERR.puts after_guard(2)
STDERR.puts after_guard(0)
STDERR.puts nested(3)
STDERR.puts before_guard(4)
STDERR.puts before_guard(0)'

# A closure that writes the guarded local must keep it nilable: both compilers
# reject the program.
REJECTS=()
add_reject() {
  REJECTS+=("$1")
  printf '%s\n' "$2" > "$WORK_DIR/$1.cr"
}

add_reject closure_write_rejected "$COMMON"'
def m(k : Int32) : Int32
  a = get(k)
  return 0 unless a
  pr = -> { a = nil; 1 }
  pr.call
  src(a)
end

puts m(1)'

# A proc created before the guard may run while the local is still nil.
add_reject proc_before_guard_rejected "$COMMON"'
def m(k : Int32) : Int32
  a = get(k)
  pr = -> { src(a) }
  return 0 unless a
  pr.call
end

puts m(1)'

stderr_of() {
  awk '/^=== STDERR ===$/ { on = 1; next } /^\[EXIT: / { on = 0 } on' "$1"
}

check_output() {
  local label="$1" name="$2" run_log="$3"
  if stderr_of "$run_log" | diff -u "$WORK_DIR/$name.want" - > "$WORK_DIR/$name.$label.diff"; then
    return 0
  fi
  return 1
}

# Original Crystal first, so the expected outputs themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for name in "${CASES[@]}"; do
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if ! check_output orig "$name" "$WORK_DIR/$name.orig.run"; then
      printf 'ORACLE FAIL: original output differs for %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.diff" >&2
      exit 2
    fi
  done
fi

if [[ -n "$CRYSTAL_BIN" ]]; then
  for name in "${REJECTS[@]}"; do
    if CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original accepts %s\n' "$name" >&2
      exit 2
    fi
  done
fi

failures=0
for name in "${REJECTS[@]}"; do
  "$SAFE_RUNNER" "$ADAMAS_BIN" 600 8192 "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$WORK_DIR/$name.log" 2>&1 || true
  if [[ -x "$WORK_DIR/$name.adamas" ]] || ! grep -q 'no overload matches src' "$WORK_DIR/$name.log"; then
    printf 'FAIL %s: nilable local was narrowed\n' "$name" >&2
    failures=$((failures + 1))
  else
    printf 'PASS %s\n' "$name"
  fi
done

for name in "${CASES[@]}"; do
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 600 8192 "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ ! -x "$WORK_DIR/$name.adamas" ]]; then
    printf 'FAIL %s: compile failed\n' "$name" >&2
    grep -v '^\[RUN_SAFE' "$log" | grep -m3 -i 'error\|overload' >&2 || tail -5 "$log" >&2
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  if check_output adamas "$name" "$run_log"; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s: output differs\n' "$name" >&2
    cat "$WORK_DIR/$name.adamas.diff" >&2
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d proc-captured guard-narrowing case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all proc-captured guard-narrowing cases passed\n'
