#!/usr/bin/env bash
# Regression: `x.as?(T)` with a primitive target is a real `T | Nil` value.
#
# lower_as_question encoded every `as?` result as a nullable pointer
# (`__adamas_select_ptr`: select is_a, obj, null). A primitive value has no
# null to spare: the backend sign-extended `9` into the pointer `0x9`, and the
# narrowed read loaded from that address (SIGSEGV). A statically failing
# test (`Box | Nil` to Int32) kept the Int32 carrier, so `v.is_a?(Nil)` was
# false. An ivar assigned from `as?(Int32)` was inferred as plain Int32.
#
# A primitive target now lowers to an is_a branch that unwraps the matching
# member and wraps it, or nil, into `Nil | T`; a test that cannot match
# yields nil directly. Reference targets (Box, classes) keep the pointer
# carrier and are the controls.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-as_question_value_target.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > union_member_truthy.cr <<'CR'
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
def hh(x : Int32) : Int32 | Box(Int32)
  x == 1 ? 9 : Box.new(x)
end
v = hh(1).as?(Int32)
LibC.exit(v ? take(v) : 7)
CR

cat > union_member_is_a.cr <<'CR'
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
def hh(x : Int32) : Int32 | Box(Int32)
  x == 1 ? 9 : Box.new(x)
end
v = hh(1).as?(Int32)
LibC.exit(v.is_a?(Int32) ? take(v) : 7)
CR

cat > union_member_in_def.cr <<'CR'
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
def hh(x : Int32) : Int32 | Box(Int32)
  x == 1 ? 9 : Box.new(x)
end
def f : Int32
  v = hh(1).as?(Int32)
  v ? take(v) : 7
end
LibC.exit(f)
CR

cat > primitive_receiver.cr <<'CR'
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
def hh(x : Int32) : Int32 | Box(Int32)
  x == 1 ? 9 : Box.new(x)
end
v = 9.as?(Int32)
LibC.exit(v ? take(v) : 7)
CR

cat > ivar_member.cr <<'CR'
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
def hh(x : Int32) : Int32 | Box(Int32)
  x == 1 ? 9 : Box.new(x)
end
class Hold
  def initialize(x : Int32)
    @v = hh(x).as?(Int32)
  end
  def get : Int32
    v = @v
    v ? v : 7
  end
end
LibC.exit(Hold.new(1).get)
CR

cat > ivar_nil.cr <<'CR'
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
def hh(x : Int32) : Int32 | Box(Int32)
  x == 1 ? 9 : Box.new(x)
end
class Hold
  def initialize(x : Int32)
    @v = hh(x).as?(Int32)
  end
  def get : Int32
    v = @v
    v ? v : 7
  end
end
LibC.exit(Hold.new(2).get)
CR

cat > assign_in_condition.cr <<'CR'
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
def hh(x : Int32) : Int32 | Box(Int32)
  x == 1 ? 9 : Box.new(x)
end
if v = hh(1).as?(Int32)
  LibC.exit(take(v))
end
LibC.exit(7)
CR

cat > or_default_nil.cr <<'CR'
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
def hh(x : Int32) : Int32 | Box(Int32)
  x == 1 ? 9 : Box.new(x)
end
v = hh(2).as?(Int32) || 5
LibC.exit(take(v))
CR

cat > numeric_union_member.cr <<'CR'
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
def hh(x : Int32) : Int32 | Box(Int32)
  x == 1 ? 9 : Box.new(x)
end
def hn(x : Int32) : Int32 | Int64
  x == 1 ? 9 : 3_i64
end
v = hn(1).as?(Int32)
LibC.exit(v ? take(v) : 7)
CR

cat > or_default_call_arg.cr <<'CR'
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
def hh(x : Int32) : Int32 | Box(Int32)
  x == 1 ? 9 : Box.new(x)
end
LibC.exit(take(hh(1).as?(Int32) || 4))
CR

cat > statically_nil_is_a_nil.cr <<'CR'
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
def hh(x : Int32) : Int32 | Box(Int32)
  x == 1 ? 9 : Box.new(x)
end
def hs(x : Int32) : Box(Int32) | Nil
  x == 1 ? Box.new(x) : nil
end
v = hs(2).as?(Int32)
LibC.exit(v.is_a?(Nil) ? 6 : 7)
CR

cat > statically_nil_union.cr <<'CR'
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
def hh(x : Int32) : Int32 | Box(Int32)
  x == 1 ? 9 : Box.new(x)
end
def bb(x : Int32) : Box(Int32) | Nil
  x == 1 ? Box.new(x) : nil
end
v = bb(1).as?(Int32)
LibC.exit(v ? take(v) : 7)
CR

cat > statically_nil_primitive.cr <<'CR'
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
def hh(x : Int32) : Int32 | Box(Int32)
  x == 1 ? 9 : Box.new(x)
end
v = 5_i64.as?(Int32)
LibC.exit(v ? take(v) : 7)
CR

cat > bool_member.cr <<'CR'
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
def hh(x : Int32) : Int32 | Box(Int32)
  x == 1 ? 9 : Box.new(x)
end
def bq(x : Int32) : Bool | Box(Int32)
  x == 1 ? true : Box.new(x)
end
v = bq(1).as?(Bool)
LibC.exit(v.is_a?(Bool) ? (v ? 3 : 4) : 7)
CR

cat > float_member.cr <<'CR'
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
def hh(x : Int32) : Int32 | Box(Int32)
  x == 1 ? 9 : Box.new(x)
end
def hf(x : Int32) : Float64 | Box(Int32)
  x == 1 ? 2.5 : Box.new(x)
end
v = hf(1).as?(Float64)
LibC.exit(v ? (v > 2.0 ? 3 : 4) : 7)
CR

cat > char_member.cr <<'CR'
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
def hh(x : Int32) : Int32 | Box(Int32)
  x == 1 ? 9 : Box.new(x)
end
def hc(x : Int32) : Char | Box(Int32)
  x == 1 ? 'a' : Box.new(x)
end
v = hc(1).as?(Char)
LibC.exit(v ? (v == 'a' ? 3 : 4) : 7)
CR

cat > yield_wrapped_member.cr <<'CR'
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
  v ? take(v) : 7
end
LibC.exit(g { |x| x == 1 ? 9 : Box.new(x) })
CR

cat > nil_path_control.cr <<'CR'
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
def hh(x : Int32) : Int32 | Box(Int32)
  x == 1 ? 9 : Box.new(x)
end
v = hh(2).as?(Int32)
LibC.exit(v ? take(v) : 7)
CR

cat > reference_target_control.cr <<'CR'
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
def hh(x : Int32) : Int32 | Box(Int32)
  x == 1 ? 9 : Box.new(x)
end
v = hh(1).as?(Box(Int32))
LibC.exit(v ? 3 : 7)
CR

cat > class_member_control.cr <<'CR'
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
def hh(x : Int32) : Int32 | Box(Int32)
  x == 1 ? 9 : Box.new(x)
end
class Rr
  def w : Int32; 4; end
end
class Qq
end
def pp(x : Int32) : Rr | Qq
  x == 1 ? Rr.new : Qq.new
end
v = pp(1).as?(Rr)
LibC.exit(v ? v.w : 7)
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

check union_member_truthy 9
check union_member_is_a 9
check union_member_in_def 9
check primitive_receiver 9
check ivar_member 9
check ivar_nil 7
check assign_in_condition 9
check or_default_nil 5
check numeric_union_member 9
check or_default_call_arg 9
check statically_nil_is_a_nil 6
check statically_nil_union 7
check statically_nil_primitive 7
check bool_member 3
check float_member 3
check char_member 3
check yield_wrapped_member 9
check nil_path_control 7
check reference_target_control 7
check class_member_control 4

[[ $fail == 0 ]] || exit 1
printf 'PASS as_question_value_target\n'
