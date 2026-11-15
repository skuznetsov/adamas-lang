#!/usr/bin/env bash
# Regression: a captured block `&func : Int32 -> _` binds its `_` result to
# the block body's type when the def also has an untyped positional param.
#
# `def fm(n, &func : Int32 -> _)` is lowered under the shape-keyed block
# target `fm$Int32_block`, which has no def of its own: the durable shape
# record names the shared `fm$block$arity1` def. block_return_type_param_name
# looked the def up only by the mangled and base names, found nothing, and
# so never recorded `_ => Int32`; the body typed `func` as
# `Proc(Int32, Void)`, so `g(func)` failed ("no overload matches" or
# "must return Int32, but it is returning Nil"). A typed positional
# param or none at all keeps a registered def name and is the control.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-shape_keyed_block_return_param.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > untyped_positional_proc_restriction.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
struct Proc
  @[Primitive(:proc_call)]
  def call(*args : *T) : R
  end
end
class Src
  def next : Int32
    3
  end
end
def g(f : Proc(Int32, Int32)) : Int32
  f.call(3)
end
def fm(n, &func : Int32 -> _)
  g(func)
end
LibC.exit(fm(1) { |x| x &+ 4 })
CR

cat > untyped_positional_untyped_callee.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
struct Proc
  @[Primitive(:proc_call)]
  def call(*args : *T) : R
  end
end
class Src
  def next : Int32
    3
  end
end
def g(f) : Int32
  f.call(3)
end
def fm(n, &func : Int32 -> _)
  g(func)
end
LibC.exit(fm(1) { |x| x &+ 4 })
CR

cat > untyped_positional_generic_typeof.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
struct Proc
  @[Primitive(:proc_call)]
  def call(*args : *T) : R
  end
end
class Src
  def next : Int32
    3
  end
end
class H(F)
  def initialize(@func : F); end
  def run : Int32
    3
  end
end
def fm(n, &func : Int32 -> _)
  H(typeof(func)).new(func)
end
LibC.exit(fm(1) { |x| x &+ 4 }.run)
CR

cat > untyped_positional_explicit_proc_arg.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
struct Proc
  @[Primitive(:proc_call)]
  def call(*args : *T) : R
  end
end
class Src
  def next : Int32
    3
  end
end
class H(F)
  def initialize(@func : F); end
  def run : Int32
    3
  end
end
def fm(n, &func : Int32 -> _)
  H(Proc(Int32, Int32)).new(func)
end
LibC.exit(fm(1) { |x| x &+ 4 }.run)
CR

cat > untyped_iter_typeof_func.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
struct Proc
  @[Primitive(:proc_call)]
  def call(*args : *T) : R
  end
end
class Src
  def next : Int32
    3
  end
end
class H(F)
  def initialize(@func : F); end
  def run : Int32
    3
  end
end
def fm(iter, &func : Int32 -> _)
  H(typeof(func)).new(func)
end
LibC.exit(fm(Src.new) { |x| x &+ 4 }.run)
CR

cat > untyped_iter_explicit_element.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
struct Proc
  @[Primitive(:proc_call)]
  def call(*args : *T) : R
  end
end
class Src
  def next : Int32
    3
  end
end
class FM(T, F)
  def initialize(@func : F); end
  def take(x : T) : T
    x
  end
end
def fm(iter, &func : Int32 -> _)
  FM(Int32, typeof(func)).new(func)
end
LibC.exit(fm(Src.new) { |x| x &+ 4 }.take(7))
CR

cat > untyped_iter_typeof_element_type.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
struct Proc
  @[Primitive(:proc_call)]
  def call(*args : *T) : R
  end
end
class Src
  def next : Int32
    3
  end
end
class FM(T, F)
  def initialize(@func : F); end
  def self.element_type(iter, func)
    value = iter.next
    func.call value
  end
  def take(x : T) : T
    x
  end
end
def fm(iter, &func : Int32 -> _)
  FM(typeof(FM.element_type(iter, func)), typeof(func)).new(func)
end
LibC.exit(fm(Src.new) { |x| x &+ 4 }.take(7))
CR

cat > two_arg_shapes.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
struct Proc
  @[Primitive(:proc_call)]
  def call(*args : *T) : R
  end
end
class Src
  def next : Int32
    3
  end
end
def g(f) : Int32
  f.call(3)
end
def fm(n, &func : Int32 -> _)
  g(func)
end
a = fm(1) { |x| x &+ 4 }
b = fm(true) { |x| x &+ 10 }
LibC.exit(a &+ b)
CR

cat > two_block_returns_one_shape.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
struct Proc
  @[Primitive(:proc_call)]
  def call(*args : *T) : R
  end
end
class Src
  def next : Int32
    3
  end
end
def g(f)
  f.call(3)
end
def fm(n, &func : Int32 -> _)
  g(func)
end
a = fm(1) { |x| x &+ 4 }
b = fm(1) { |x| x == 3 }
LibC.exit(a &+ (b ? 10 : 20))
CR

cat > no_positional_control.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
struct Proc
  @[Primitive(:proc_call)]
  def call(*args : *T) : R
  end
end
class Src
  def next : Int32
    3
  end
end
def g(f : Proc(Int32, Int32)) : Int32
  f.call(3)
end
def fm(&func : Int32 -> _)
  g(func)
end
LibC.exit(fm { |x| x &+ 4 })
CR

cat > typed_positional_control.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
struct Proc
  @[Primitive(:proc_call)]
  def call(*args : *T) : R
  end
end
class Src
  def next : Int32
    3
  end
end
class H(F)
  def initialize(@func : F); end
  def run : Int32
    3
  end
end
def fm(n : Int32, &func : Int32 -> _)
  H(typeof(func)).new(func)
end
LibC.exit(fm(1) { |x| x &+ 4 }.run)
CR

cat > no_positional_untyped_callee_control.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
struct Proc
  @[Primitive(:proc_call)]
  def call(*args : *T) : R
  end
end
class Src
  def next : Int32
    3
  end
end
def g(f) : Int32
  f.call(3)
end
def fm(&func : Int32 -> _)
  g(func)
end
LibC.exit(fm { |x| x &+ 4 })
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

check untyped_positional_proc_restriction 7
check untyped_positional_untyped_callee 7
check untyped_positional_generic_typeof 3
check untyped_positional_explicit_proc_arg 3
check untyped_iter_typeof_func 3
check untyped_iter_explicit_element 7
check untyped_iter_typeof_element_type 7
check two_arg_shapes 20
check two_block_returns_one_shape 17
check no_positional_control 7
check typed_positional_control 3
check no_positional_untyped_callee_control 7

[[ $fail == 0 ]] || exit 1
printf 'PASS shape_keyed_block_return_param\n'
