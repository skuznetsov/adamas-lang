#!/usr/bin/env bash
# Regression: a yield wrapped in a type test or cast still passes its
# arguments to the block.
#
# `(yield 1).is_a?(T)`, `.as(T)`, `.as?(T)` and `.responds_to?(:m)` parse as
# IsA/As/AsQuestion/RespondsTo nodes. collect_yield_arg_lists did not descend
# into them, so the yield's argument types were never seen and the block
# parameter fell back to Pointer (`undefined method 'new' for Box(Pointer)`).
# contains_yield_in_expr? and yield_in_value_position? had the same gap, so a
# def without `&` whose only yield sat inside such a node was not treated
# as a yielding def. A yield bound to a local first (`v = yield 1;
# v.is_a?(Int32)`) is the control.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-yield_type_test_wrapper.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > is_a_if_condition.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
class Box(T)
  def initialize(@v : T); end
  def v; @v; end
end
def take(x : Int32) : Int32
  x
end
def g(&) : Int32
  if (yield 1).is_a?(Int32)
    8
  else
    7
  end
end
LibC.exit(g { |x| x == 1 ? 9 : Box.new(x) })
CR

cat > as_call_argument.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
class Box(T)
  def initialize(@v : T); end
  def v; @v; end
end
def take(x : Int32) : Int32
  x
end
def g(&) : Int32
  take((yield 1).as(Int32))
end
LibC.exit(g { |x| Box.new(x).v &+ 4 })
CR

cat > as_question_assign.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
class Box(T)
  def initialize(@v : T); end
  def v; @v; end
end
def take(x : Int32) : Int32
  x
end
def g(&) : Int32
  v = (yield 1).as?(Int32)
  v ? 5 : 7
end
LibC.exit(g { |x| x == 1 ? 9 : Box.new(x) })
CR

cat > responds_to_ternary.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
class Box(T)
  def initialize(@v : T); end
  def v; @v; end
end
def take(x : Int32) : Int32
  x
end
def g(&) : Int32
  (yield 1).responds_to?(:v) ? 4 : 3
end
LibC.exit(g { |x| x == 1 ? 9 : Box.new(x) })
CR

cat > is_a_without_block_param.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
class Box(T)
  def initialize(@v : T); end
  def v; @v; end
end
def take(x : Int32) : Int32
  x
end
def g : Int32
  (yield 1).is_a?(Int32) ? 8 : 7
end
LibC.exit(g { |x| x == 1 ? 9 : Box.new(x) })
CR

cat > is_a_assign_in_condition.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
class Box(T)
  def initialize(@v : T); end
  def v; @v; end
end
def take(x : Int32) : Int32
  x
end
def g(&) : Int32
  if (v = yield 1).is_a?(Int32)
    take(v)
  else
    7
  end
end
LibC.exit(g { |x| x == 1 ? 9 : Box.new(x) })
CR

cat > is_a_multiple_callsites.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
class Box(T)
  def initialize(@v : T); end
  def v; @v; end
end
def take(x : Int32) : Int32
  x
end
def g(&) : Int32
  (yield 1).is_a?(Int32) ? 8 : 7
end
def k : Int32
  g { |x| x == 1 ? 9 : Box.new(x) } &+ g { |x| 9 }
end
LibC.exit(k &+ g { |x| x == 2 ? 9 : Box.new(x) })
CR

cat > is_a_false_branch.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
class Box(T)
  def initialize(@v : T); end
  def v; @v; end
end
def take(x : Int32) : Int32
  x
end
def g(&) : Int32
  (yield 2).is_a?(Int32) ? 8 : 7
end
LibC.exit(g { |x| x == 1 ? 9 : Box.new(x) })
CR

cat > local_then_is_a_control.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
class Box(T)
  def initialize(@v : T); end
  def v; @v; end
end
def take(x : Int32) : Int32
  x
end
def g(&) : Int32
  v = yield 1
  v.is_a?(Int32) ? take(v) : 7
end
LibC.exit(g { |x| x == 1 ? 9 : Box.new(x) })
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

check is_a_if_condition 8
check as_call_argument 5
check as_question_assign 5
check responds_to_ternary 3
check is_a_without_block_param 8
check is_a_assign_in_condition 9
check is_a_multiple_callsites 23
check is_a_false_branch 7
check local_then_is_a_control 9

[[ $fail == 0 ]] || exit 1
printf 'PASS yield_type_test_wrapper\n'
