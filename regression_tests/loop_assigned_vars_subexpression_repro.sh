#!/usr/bin/env bash
# Regression: loop phi discovery must find assignments and yields in every
# subexpression of the loop body, conditions included.
#
# collect_assigned_vars_in_expr only walked statement bodies and a few
# expression kinds. An assignment or an inlined yield (whose block writes a
# caller local) in a ternary, an if/elsif/unless/while condition, a unary
# operand, a call receiver or a nested `until` got no loop phi, so the loop
# kept the pre-loop value. Every node kind is now walked through the shared
# child walker; proc literal bodies stay excluded (their writes are closure
# cells). A plain nested loop and a proc-literal write are controls.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-loop_assigned_vars_subexpression.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > ternary_yield_both_arms.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  while n < fmt
    n == 0 ? yield(1) : yield(2)
    n &+= 1
  end
end
acc = 0
pr(3) { |v| acc = acc &* 10 &+ v }
LibC.exit(acc & 255)
CR

cat > toplevel_ternary_assign.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
acc = 0
n = 0
while n < 3
  r = n == 1 ? (acc = acc &* 10 &+ 4) : (acc = acc &* 10 &+ 1)
  n &+= 1
end
LibC.exit(acc & 255)
CR

cat > if_condition_assign.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
acc = 0
n = 0
while n < 4
  if (acc = acc &* 2 &+ n) > 100
    n &+= 0
  end
  n &+= 1
end
LibC.exit(acc & 255)
CR

cat > unless_not_yield_condition.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  c = 0
  while n < fmt
    c &+= 1 unless !yield(n)
    n &+= 1
  end
  c
end
acc = 0
r = pr(3) { |v| acc = acc &* 10 &+ v &+ 1; v != 1 }
LibC.exit((acc &+ r) & 255)
CR

cat > yield_call_receiver.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  s = 0
  while n < fmt
    s = s &+ (yield n).abs
    n &+= 1
  end
  s
end
struct Int32
  def abs : Int32
    self < 0 ? 0 &- self : self
  end
end
acc = 0
r = pr(3) { |v| acc = acc &* 10 &+ v &+ 1; 0 &- v }
LibC.exit((acc &+ r) & 255)
CR

cat > if_yield_compare_condition.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  while n < fmt
    if yield(n) > 1
      n &+= 1
    end
    n &+= 1
  end
end
acc = 0
pr(5) { |v| acc = acc &* 10 &+ v &+ 1; v }
LibC.exit(acc & 255)
CR

cat > unary_yield_operand.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct Int32
  def - : Int32
    0 &- self
  end
end
def pr(fmt : Int32, &)
  n = 0
  s = 0
  while n < fmt
    s = s &+ -(yield n)
    n &+= 1
  end
  s
end
acc = 0
r = pr(3) { |v| acc = acc &* 10 &+ v &+ 1; 0 &- v }
LibC.exit((acc &+ r) & 255)
CR

cat > ternary_yield_condition.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  while n < fmt
    (yield n) ? (n &+= 1) : nil
    n &+= 1
  end
end
acc = 0
pr(5) { |v| acc = acc &* 10 &+ v &+ 1; v == 1 }
LibC.exit(acc & 255)
CR

cat > nested_until_body_assign.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
acc = 0
n = 0
while n < 3
  k = 0
  until k == 2
    acc = acc &* 2 &+ 1
    k &+= 1
  end
  n &+= 1
end
LibC.exit(acc & 255)
CR

cat > elsif_condition_assign.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
acc = 0
n = 0
while n < 5
  if n == 0
    n &+= 0
  elsif (acc = acc &* 2 &+ n) > 1000
    n &+= 0
  end
  n &+= 1
end
LibC.exit(acc & 255)
CR

cat > nested_while_yield_condition.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  while n < fmt
    while (yield n) < 0
      n &+= 0
    end
    n &+= 1
  end
end
acc = 0
pr(3) { |v| acc = acc &* 10 &+ v &+ 1; v }
LibC.exit(acc & 255)
CR

cat > nested_while_condition_assign_control.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def nx(i : Int32) : Int32?
  i < 3 ? i : nil
end
x = nil
s = 0
n = 0
while n < 2
  i = 0
  while (x = nx(i))
    s &+= x
    i &+= 1
  end
  n &+= 1
end
LibC.exit(x.nil? ? s : 99)
CR

cat > proc_literal_write_control.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
acc = 0
n = 0
f = ->(x : Int32) { acc = acc &+ x; nil }
while n < 4
  f.call(n)
  n &+= 1
end
LibC.exit(acc & 255)
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

check ternary_yield_both_arms 122
check toplevel_ternary_assign 141
check if_condition_assign 11
check unless_not_yield_condition 125
check yield_call_receiver 126
check if_yield_compare_condition 211
check unary_yield_operand 126
check ternary_yield_condition 221
check nested_until_body_assign 63
check elsif_condition_assign 26
check nested_while_yield_condition 123
check nested_while_condition_assign_control 6
check proc_literal_write_control 6

[[ $fail == 0 ]] || exit 1
printf 'PASS loop_assigned_vars_subexpression\n'
