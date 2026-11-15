#!/usr/bin/env bash
# Regression: a loop in inlined callee code must carry a yielded block's
# caller local through the caller frame, even when ctx binds that name.
#
# A callee loop that carries a caller local written by the yielded block
# (`acc` in `while c; yield x; end`) also binds the caller's name in ctx: to
# its header phi while the loop is lowered and to its exit value after it.
# A nested loop, or a later loop in the same callee, took that mirror for a
# callee local and built a ctx phi the block's writes never reach (they go to
# the caller frame and the loop back-edge values), so the writes of every
# iteration but the last were lost. Controls: a callee local with the
# caller's name, a loop inside the block body, a block defined in callee
# code, and yields before a single loop.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-inline_nested_loop_frame_var.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > outer_yield_then_nested_loop.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  while n < fmt
    yield 7
    m = 0
    while m < 2
      yield m &+ 1
      m &+= 1
    end
    n &+= 1
  end
end
acc = 0
pr(2) { |v| acc = acc &* 10 &+ v }
LibC.exit(acc & 255)
CR

cat > nested_loops_only.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  while n < fmt
    m = 0
    while m < 2
      yield m &+ 1
      m &+= 1
    end
    n &+= 1
  end
end
acc = 0
pr(2) { |v| acc = acc &* 10 &+ v }
LibC.exit(acc & 255)
CR

cat > nested_loop_then_yield_in_def.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  while n < fmt
    m = 0
    while m < 2
      yield m &+ 1
      m &+= 1
    end
    yield 5
    n &+= 1
  end
end
def run : Int32
  acc = 0
  pr(2) { |v| acc = acc &* 3 &+ v }
  acc
end
LibC.exit(run & 255)
CR

cat > two_sequential_loops.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  while n < fmt
    yield 1
    n &+= 1
  end
  m = 0
  while m < fmt
    yield 2
    m &+= 1
  end
end
acc = 0
pr(2) { |v| acc = acc &* 10 &+ v }
LibC.exit(acc & 255)
CR

cat > three_level_nesting.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  a = 0
  while a < 2
    b = 0
    while b < 2
      c = 0
      while c < 2
        yield c &+ 1
        c &+= 1
      end
      b &+= 1
    end
    a &+= 1
  end
end
acc = 0
pr(2) { |v| acc = acc &* 3 &+ v }
LibC.exit(acc & 255)
CR

cat > two_nested_loops_in_outer.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  while n < fmt
    m = 0
    while m < 2
      yield m &+ 1
      m &+= 1
    end
    m = 0
    while m < 2
      yield m &+ 3
      m &+= 1
    end
    n &+= 1
  end
end
acc = 0
pr(2) { |v| acc = acc &* 3 &+ v }
LibC.exit(acc & 255)
CR

cat > yield_between_sequential_loops.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  while n < fmt
    yield 1
    n &+= 1
  end
  yield 5
  m = 0
  while m < fmt
    yield 2
    m &+= 1
  end
end
acc = 0
pr(2) { |v| acc = acc &* 10 &+ v }
LibC.exit(acc & 255)
CR

cat > break_loop_then_loop.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  while n < 10
    yield n
    break if n == fmt
    n &+= 1
  end
  m = 0
  while m < 2
    yield 7
    m &+= 1
  end
end
acc = 0
pr(2) { |v| acc = acc &* 10 &+ v }
LibC.exit(acc & 255)
CR

cat > loop_then_nested_loops.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  while n < fmt
    yield 1
    n &+= 1
  end
  n = 0
  while n < fmt
    m = 0
    while m < 2
      yield 2
      m &+= 1
    end
    n &+= 1
  end
end
acc = 0
pr(2) { |v| acc = acc &* 3 &+ v }
LibC.exit(acc & 255)
CR

cat > nested_loop_in_then_arm.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  while n < fmt
    if n == 1
      m = 0
      while m < 2
        yield m &+ 1
        m &+= 1
      end
    else
      yield 7
    end
    n &+= 1
  end
end
acc = 0
pr(3) { |v| acc = acc &* 10 &+ v }
LibC.exit(acc & 255)
CR

cat > callee_local_same_name_control.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  acc = 100
  n = 0
  while n < fmt
    m = 0
    while m < 2
      acc &+= 1
      yield m &+ 1
      m &+= 1
    end
    n &+= 1
  end
  acc
end
acc = 0
r = pr(2) { |v| acc = acc &* 10 &+ v }
LibC.exit((acc &+ r) & 255)
CR

cat > loop_in_block_body_control.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  while n < fmt
    yield n
    n &+= 1
  end
end
acc = 0
pr(3) do |v|
  acc = acc &* 2
  k = 0
  while k < v
    acc &+= 1
    k &+= 1
  end
end
LibC.exit(acc & 255)
CR

cat > block_from_callee_code_control.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def inner(k : Int32, &)
  j = 0
  while j < k
    yield j
    j &+= 1
  end
end
def outer(fmt : Int32, &)
  t = 0
  n = 0
  while n < fmt
    inner(2) { |j| t = t &* 3 &+ j &+ 1 }
    yield t
    n &+= 1
  end
  t
end
acc = 0
r = outer(2) { |v| acc = acc &+ v }
LibC.exit((acc &+ r) & 255)
CR

cat > if_yield_then_loop_control.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  if fmt > 1
    yield 4
  else
    yield 6
  end
  m = 0
  while m < fmt
    yield m
    m &+= 1
  end
end
acc = 1
pr(3) { |v| acc = acc &* 10 &+ v }
LibC.exit(acc & 255)
CR

cat > callee_local_two_loops_control.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  acc = 0
  n = 0
  while n < fmt
    yield 1
    acc &+= 2
    n &+= 1
  end
  m = 0
  while m < fmt
    yield 3
    acc &+= 5
    m &+= 1
  end
  acc
end
acc = 0
r = pr(2) { |v| acc = acc &* 10 &+ v }
LibC.exit((acc &+ r) & 255)
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

check outer_yield_then_nested_loop 8
check nested_loops_only 188
check nested_loop_then_yield_in_def 48
check two_sequential_loops 98
check three_level_nesting 4
check two_nested_loops_in_outer 148
check yield_between_sequential_loops 2
check break_loop_then_loop 253
check loop_then_nested_loops 148
check nested_loop_in_then_arm 215
check callee_local_same_name_control 36
check loop_in_block_body_control 4
check block_from_callee_code_control 105
check if_yield_then_loop_control 188
check callee_local_two_loops_control 123

[[ $fail == 0 ]] || exit 1
printf 'PASS inline_nested_loop_frame_var\n'
