#!/usr/bin/env bash
# Regression: the body of a runtime `unless v.is_a?(T)` sees the union
# variants that fail the test.
#
# `unless v.is_a?(Int32) takeb(v) else take(v) end` over
# `Int32 | Box(Int32)` types `v` as `Box(Int32)` in the body, like the
# else arm of `if v.is_a?(Int32)`. Only the statically decided `unless`
# applied the negative is_a? filters; the runtime branch applied the
# falsy truthiness targets alone, so even an exact single-variant test
# left the whole union and the call failed with "no overload matches".
# The else arm (positive filter) is the control.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-unless_is_a_body_narrowing.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > exact_value_test_body.cr <<'CR'
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
  unless v.is_a?(Int32)
    takeb(v)
  else
    take(v)
  end
end
LibC.exit(f(1) &+ f(2))
CR

cat > exact_generic_test_body.cr <<'CR'
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
  unless v.is_a?(Box(Int32))
    take(v)
  else
    takeb(v)
  end
end
LibC.exit(f(1) &+ f(2))
CR

cat > bare_generic_test_body.cr <<'CR'
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
  unless v.is_a?(Box)
    take(v)
  else
    takeb(v)
  end
end
LibC.exit(f(1) &+ f(2))
CR

cat > yield_subject_bare_generic_body.cr <<'CR'
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
  v = yield 1
  unless v.is_a?(Box)
    take(v)
  else
    takeb(v)
  end
end
LibC.exit(g { |x| x == 1 ? 9 : Box.new(x) })
CR

cat > multi_variant_remainder_body.cr <<'CR'
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
  unless v.is_a?(Box)
    v.is_a?(Pl) ? takep(v) : take(v)
  else
    takeb(v)
  end
end
LibC.exit(f(1) &+ f(2) &+ f(3))
CR

cat > body_without_else.cr <<'CR'
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
  r = 0
  unless v.is_a?(Box)
    r = take(v)
  end
  r
end
LibC.exit(f(1) &+ f(2))
CR

cat > else_arm_positive_filter_control.cr <<'CR'
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
  unless v.is_a?(Int32)
    0
  else
    take(v)
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

check exact_value_test_body 109
check exact_generic_test_body 109
check bare_generic_test_body 109
check yield_subject_bare_generic_body 9
check multi_variant_remainder_body 139
check body_without_else 9
check else_arm_positive_filter_control 9

[[ $fail == 0 ]] || exit 1
printf 'PASS unless_is_a_body_narrowing\n'
