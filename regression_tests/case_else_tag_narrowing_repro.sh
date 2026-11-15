#!/usr/bin/env bash
# Regression: the else arm of a `case` sees only the union variants that no
# `when` tag test claimed.
#
# `case v = yield 1; when Box then ...; else take(v)` over
# `Int32 | Box(Int32)` types `v` as `Int32` in the else, as Crystal does;
# `Enumerable#flat_map` relies on it (`when Array, Iterator ... else
# ary.push(v)`). The else arm narrowed only after a nil check, so every
# other remainder kept the whole union and failed with "no overload
# matches". A value `when`, a nil check and a reassigned subject are
# controls.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-case_else_tag_narrowing.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > yield_subject_bare_generic_when.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
class Box(T)
  def initialize(@v : T); end
  def v; @v; end
end
module It(T)
end
class Pl
  def initialize(@w : Int32); end
  def w; @w; end
end
def take(x : Int32) : Int32
  x
end
def takeb(x : Box(Int32)) : Int32
  100
end
def takep(x : Pl) : Int32
  x.w
end
def h(x : Int32) : Int32 | Box(Int32)
  x == 1 ? 9 : Box.new(x)
end
def h3(x : Int32) : Int32 | Box(Int32) | Pl
  x == 1 ? 9 : (x == 2 ? Pl.new(30) : Box.new(x))
end
def g(&) : Int32
  case v = yield 1
  when Box
    takeb(v)
  else
    take(v)
  end
end
LibC.exit(g { |x| x == 1 ? 9 : Box.new(x) })
CR

cat > yield_subject_two_type_conditions.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
class Box(T)
  def initialize(@v : T); end
  def v; @v; end
end
module It(T)
end
class Pl
  def initialize(@w : Int32); end
  def w; @w; end
end
def take(x : Int32) : Int32
  x
end
def takeb(x : Box(Int32)) : Int32
  100
end
def takep(x : Pl) : Int32
  x.w
end
def h(x : Int32) : Int32 | Box(Int32)
  x == 1 ? 9 : Box.new(x)
end
def h3(x : Int32) : Int32 | Box(Int32) | Pl
  x == 1 ? 9 : (x == 2 ? Pl.new(30) : Box.new(x))
end
def g(&) : Int32
  case v = yield 1
  when Box, It
    takeb(v.as(Box(Int32)))
  else
    take(v)
  end
end
LibC.exit(g { |x| x == 1 ? 9 : Box.new(x) })
CR

cat > call_subject_bare_generic_when.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
class Box(T)
  def initialize(@v : T); end
  def v; @v; end
end
module It(T)
end
class Pl
  def initialize(@w : Int32); end
  def w; @w; end
end
def take(x : Int32) : Int32
  x
end
def takeb(x : Box(Int32)) : Int32
  100
end
def takep(x : Pl) : Int32
  x.w
end
def h(x : Int32) : Int32 | Box(Int32)
  x == 1 ? 9 : Box.new(x)
end
def h3(x : Int32) : Int32 | Box(Int32) | Pl
  x == 1 ? 9 : (x == 2 ? Pl.new(30) : Box.new(x))
end
def f(n : Int32) : Int32
  case v = h(n)
  when Box
    takeb(v)
  else
    take(v)
  end
end
LibC.exit(f(1) &+ f(2))
CR

cat > chained_whens_leave_last_variant.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
class Box(T)
  def initialize(@v : T); end
  def v; @v; end
end
module It(T)
end
class Pl
  def initialize(@w : Int32); end
  def w; @w; end
end
def take(x : Int32) : Int32
  x
end
def takeb(x : Box(Int32)) : Int32
  100
end
def takep(x : Pl) : Int32
  x.w
end
def h(x : Int32) : Int32 | Box(Int32)
  x == 1 ? 9 : Box.new(x)
end
def h3(x : Int32) : Int32 | Box(Int32) | Pl
  x == 1 ? 9 : (x == 2 ? Pl.new(30) : Box.new(x))
end
def f(n : Int32) : Int32
  v = h3(n)
  case v
  when Box
    takeb(v)
  when Pl
    takep(v)
  else
    take(v)
  end
end
LibC.exit(f(1) &+ f(2) &+ f(3))
CR

cat > multi_variant_remainder.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
class Box(T)
  def initialize(@v : T); end
  def v; @v; end
end
module It(T)
end
class Pl
  def initialize(@w : Int32); end
  def w; @w; end
end
def take(x : Int32) : Int32
  x
end
def takeb(x : Box(Int32)) : Int32
  100
end
def takep(x : Pl) : Int32
  x.w
end
def h(x : Int32) : Int32 | Box(Int32)
  x == 1 ? 9 : Box.new(x)
end
def h3(x : Int32) : Int32 | Box(Int32) | Pl
  x == 1 ? 9 : (x == 2 ? Pl.new(30) : Box.new(x))
end
def f(n : Int32) : Int32
  case v = h3(n)
  when Box
    takeb(v)
  else
    v.is_a?(Pl) ? takep(v) : take(v)
  end
end
LibC.exit(f(1) &+ f(2) &+ f(3))
CR

cat > multi_condition_when_remainder.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
class Box(T)
  def initialize(@v : T); end
  def v; @v; end
end
module It(T)
end
class Pl
  def initialize(@w : Int32); end
  def w; @w; end
end
def take(x : Int32) : Int32
  x
end
def takeb(x : Box(Int32)) : Int32
  100
end
def takep(x : Pl) : Int32
  x.w
end
def h(x : Int32) : Int32 | Box(Int32)
  x == 1 ? 9 : Box.new(x)
end
def h3(x : Int32) : Int32 | Box(Int32) | Pl
  x == 1 ? 9 : (x == 2 ? Pl.new(30) : Box.new(x))
end
def f(n : Int32) : Int32
  case v = h3(n)
  when Box, Pl
    2
  else
    take(v)
  end
end
LibC.exit(f(1) &+ f(2) &+ f(3))
CR

cat > reassigned_subject_in_when_arm.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
class Box(T)
  def initialize(@v : T); end
  def v; @v; end
end
module It(T)
end
class Pl
  def initialize(@w : Int32); end
  def w; @w; end
end
def take(x : Int32) : Int32
  x
end
def takeb(x : Box(Int32)) : Int32
  100
end
def takep(x : Pl) : Int32
  x.w
end
def h(x : Int32) : Int32 | Box(Int32)
  x == 1 ? 9 : Box.new(x)
end
def h3(x : Int32) : Int32 | Box(Int32) | Pl
  x == 1 ? 9 : (x == 2 ? Pl.new(30) : Box.new(x))
end
def f(n : Int32) : Int32
  v = h(n)
  case v
  when Box
    v = 4
    take(v)
  else
    take(v)
  end
end
LibC.exit(f(1) &+ f(2))
CR

cat > nil_when_control.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
class Box(T)
  def initialize(@v : T); end
  def v; @v; end
end
module It(T)
end
class Pl
  def initialize(@w : Int32); end
  def w; @w; end
end
def take(x : Int32) : Int32
  x
end
def takeb(x : Box(Int32)) : Int32
  100
end
def takep(x : Pl) : Int32
  x.w
end
def h(x : Int32) : Int32 | Box(Int32)
  x == 1 ? 9 : Box.new(x)
end
def h3(x : Int32) : Int32 | Box(Int32) | Pl
  x == 1 ? 9 : (x == 2 ? Pl.new(30) : Box.new(x))
end
def hn(x : Int32) : Int32?
  x == 1 ? 12 : nil
end
def f(n : Int32) : Int32
  case v = hn(n)
  when Nil
    3
  else
    take(v)
  end
end
LibC.exit(f(1) &+ f(2))
CR

cat > value_when_keeps_union_control.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
class Box(T)
  def initialize(@v : T); end
  def v; @v; end
end
module It(T)
end
class Pl
  def initialize(@w : Int32); end
  def w; @w; end
end
def take(x : Int32) : Int32
  x
end
def takeb(x : Box(Int32)) : Int32
  100
end
def takep(x : Pl) : Int32
  x.w
end
def h(x : Int32) : Int32 | Box(Int32)
  x == 1 ? 9 : Box.new(x)
end
def h3(x : Int32) : Int32 | Box(Int32) | Pl
  x == 1 ? 9 : (x == 2 ? Pl.new(30) : Box.new(x))
end
struct Int32
  def ===(other) : Bool
    false
  end
end
def f(n : Int32) : Int32
  case v = h(n)
  when 5
    1
  else
    v.is_a?(Int32) ? take(v) : 40
  end
end
LibC.exit(f(1) &+ f(2))
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

check yield_subject_bare_generic_when 9
check yield_subject_two_type_conditions 9
check call_subject_bare_generic_when 109
check chained_whens_leave_last_variant 139
check multi_variant_remainder 139
check multi_condition_when_remainder 13
check reassigned_subject_in_when_arm 13
check nil_when_control 15
check value_when_keeps_union_control 49

[[ $fail == 0 ]] || exit 1
printf 'PASS case_else_tag_narrowing\n'
