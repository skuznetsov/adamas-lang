#!/usr/bin/env bash
# Regression: a block yielded through nested inlined methods assigns a local
# of an enclosing caller frame, and the innermost callee can return early
# (`return if x == 7; yield x`) on a condition known only at run time.
#
# The inline-return exit merged only the frame that called the returning
# method. An outer frame (the top-level `total` behind `all { |f| total &+= f }`)
# kept the yield path's value on the early-return path too, and when the
# merge did rebind a loop variable, the enclosing loop's back edge still used
# the saved block write, which does not dominate the exit. V2 printed 0 for
# `total` where original Crystal prints 10.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-inline_return_outer_caller_frames.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > abstract_system_run_chain.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct Ev
  @fiber : Int32
  @kind : Int32

  def initialize(@fiber, @kind)
  end

  def fiber
    @fiber
  end

  def kind
    @kind
  end
end

abstract class P
  def run(flag : Bool, &)
    system_run(flag) { |f| yield f }
  end

  private abstract def system_run(flag : Bool, & : Int32 ->) : Nil

  private def process_all(flag : Bool, &) : Nil
    e = Ev.new(5, 1)
    p = pointerof(e)
    i = 0
    while i < 2
      process_one(p) { |f| yield f }
      i &+= 1
    end
  end

  private def process_one(ev : Ev*, &)
    f = ev.value.fiber
    return if ev.value.kind == 7
    yield f
  end
end

class K < P
  private def system_run(flag : Bool, & : Int32 ->) : Nil
    process_all(flag) { |f| yield f }
  end
end

total = 0
k = K.new
k.run(true) { |f| total &+= f }
LibC.exit(total)
CR

cat > inline_loop_caller_accumulator.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct Ev
  @fiber : Int32

  def initialize(@fiber)
  end

  def fiber
    @fiber
  end
end

def one(x : Int32, &)
  return if x == 7
  yield x
end

def all(&)
  e = Ev.new(5)
  i = 0
  while i < 2
    one(e.fiber) { |f| yield f }
    i &+= 1
  end
end

total = 0
all { |f| total &+= f }
LibC.exit(total)
CR

cat > toplevel_loop_outer_frame.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct Ev
  @fiber : Int32

  def initialize(@fiber)
  end

  def fiber
    @fiber
  end
end

def one(x : Int32, &)
  return if x == 7
  yield x
end

def all(&)
  e = Ev.new(5)
  one(e.fiber) { |f| yield f }
end

total = 0
i = 0
while i < 2
  all { |f| total &+= f }
  i &+= 1
end
LibC.exit(total)
CR

cat > nested_loops.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct Ev
  @fiber : Int32

  def initialize(@fiber)
  end

  def fiber
    @fiber
  end
end

def one(x : Int32, &)
  return if x == 7
  yield x
end

def all(&)
  e = Ev.new(5)
  i = 0
  while i < 2
    one(e.fiber) { |f| yield f }
    i &+= 1
  end
end

total = 0
j = 0
while j < 2
  all { |f| total &+= f }
  j &+= 1
end
LibC.exit(total)
CR

cat > two_accumulators.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct Ev
  @fiber : Int32

  def initialize(@fiber)
  end

  def fiber
    @fiber
  end
end

def one(x : Int32, &)
  return if x == 7
  yield x
end

def all(&)
  e = Ev.new(5)
  i = 0
  while i < 2
    one(e.fiber) { |f| yield f }
    i &+= 1
  end
end

total = 0
seen = 0
all do |f|
  total &+= f
  seen = total
end
LibC.exit(total &* 10 &+ seen)
CR

cat > early_return_taken.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct Ev
  @fiber : Int32

  def initialize(@fiber)
  end

  def fiber
    @fiber
  end
end

def one(x : Int32, &)
  return if x == 7
  yield x
end

def all(&)
  e = Ev.new(5)
  i = 0
  while i < 3
    one(e.fiber &+ i) { |f| yield f }
    i &+= 1
  end
end

total = 0
all { |f| total &+= f }
LibC.exit(total)
CR

cat > block_break_edge.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct Ev
  @fiber : Int32

  def initialize(@fiber)
  end

  def fiber
    @fiber
  end
end

def one(x : Int32, &)
  return if x == 7
  yield x
end

def all(v : Int32, &)
  e = Ev.new(v)
  one(e.fiber) { |f| yield f }
  100
end

total = 0
i = 0
r = 0
while i < 4
  v = i == 1 ? 7 : 5
  r = all(v) do |f|
    total &+= f
    break 3 if i == 2
  end
  total &+= r
  i &+= 1
end
LibC.exit(total)
CR

cat > nilable_last_value.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct Ev
  @fiber : Int32

  def initialize(@fiber)
  end

  def fiber
    @fiber
  end
end

def one(x : Int32, &)
  return if x == 7
  yield x
end

def all(v : Int32, &)
  e = Ev.new(v)
  one(e.fiber) { |f| yield f }
end

last = nil
i = 0
while i < 3
  v = i == 2 ? 7 : 5 &+ i
  all(v) { |f| last = f }
  i &+= 1
end
LibC.exit(last || 99)
CR

cat > sequential_calls_without_loop.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct Ev
  @fiber : Int32

  def initialize(@fiber)
  end

  def fiber
    @fiber
  end
end

def one(x : Int32, &)
  return if x == 7
  yield x
end

def all(v : Int32, &)
  e = Ev.new(v)
  one(e.fiber) { |f| yield f }
end

def pick(n : Int32)
  n &* 7
end

total = 0
all(pick(1)) { |f| total &+= f }
all(5) { |f| total &+= f &* 2 }
LibC.exit(total)
CR

cat > three_levels_nested_loop.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct Ev
  @fiber : Int32

  def initialize(@fiber)
  end

  def fiber
    @fiber
  end
end

def one(x : Int32, &)
  return if x == 7
  yield x
end

def two(x : Int32, &)
  return if x == 9
  one(x) { |f| yield f }
end

def all(v : Int32, &)
  e = Ev.new(v)
  two(e.fiber) { |f| yield f }
end

total = 0
seen = 0
i = 0
while i < 4
  v = i == 1 ? 7 : (i == 2 ? 9 : 5)
  j = 0
  while j < 2
    all(v) { |f| total &+= f; seen &+= 1 }
    j &+= 1
  end
  i &+= 1
end
LibC.exit(total &+ seen &* 100)
CR

cat > method_local_loop.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct Ev
  @fiber : Int32

  def initialize(@fiber)
  end

  def fiber
    @fiber
  end
end

def one(x : Int32, &)
  return if x == 7
  yield x
end

def all(v : Int32, &)
  e = Ev.new(v)
  one(e.fiber) { |f| yield f }
end

def run(n : Int32)
  total = 0
  i = 0
  while i < n
    v = i == 1 ? 7 : 3
    all(v) { |f| total &+= f }
    i &+= 1
  end
  total
end

LibC.exit(run(4))
CR

exit_code() {
  local out
  out="$("$safe" "$1" 5 256 2>&1 || true)"
  printf '%s\n' "$out" | sed -n 's/^\[EXIT: \([0-9-]*\)\].*/\1/p' | tail -1
}

fail=0
check() {
  local case_name="$1" want="$2" got_original got_candidate
  "$safe" "$original" 120 4096 build "$case_name.cr" --prelude=empty --single-module \
    --no-debug "${original_flags[@]}" -o "$case_name.original" > "$case_name.original.log" 2>&1 ||
    { cat "$case_name.original.log" >&2; echo "ORACLE_BUILD_FAIL $case_name"; fail=1; return; }
  got_original="$(exit_code "$work/$case_name.original")"
  if [[ "$got_original" != "$want" ]]; then
    echo "ORACLE_MISMATCH $case_name: original=$got_original expected=$want"; fail=1; return
  fi
  if ! "$safe" "$candidate" 120 4096 "$case_name.cr" --no-prelude --no-debug \
      --no-ast-cache --no-llvm-cache -o "$case_name.candidate" > "$case_name.candidate.log" 2>&1; then
    echo "FAIL $case_name: candidate compile failed"
    grep -a -m3 -i error "$case_name.candidate.log" || true
    fail=1; return
  fi
  got_candidate="$(exit_code "$work/$case_name.candidate")"
  if [[ "$got_candidate" != "$want" ]]; then
    echo "FAIL $case_name: candidate=$got_candidate expected=$want"; fail=1; return
  fi
  echo "ok $case_name"
}

check abstract_system_run_chain 10
check inline_loop_caller_accumulator 10
check toplevel_loop_outer_frame 10
check nested_loops 20
check two_accumulators 110
check early_return_taken 11
check block_break_edge 62
check nilable_last_value 6
check sequential_calls_without_loop 10
check three_levels_nested_loop 164
check method_local_loop 9

[[ $fail == 0 ]] || exit 1
printf 'PASS inline_return_outer_caller_frames\n'
