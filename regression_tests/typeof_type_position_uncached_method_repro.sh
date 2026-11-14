#!/usr/bin/env bash
# Regression: a type-position typeof (`Sl(typeof(dq.buffer.value))`) must not
# depend on whether lowering already published the receiver method's result.
#
# The textual typeof resolver read method results only from @function_types.
# When the generic receiver was first monomorphized inside a force-lower
# generation that did not complete, its getter result was rolled back with the
# generation, and the typeof fell to the unknown sentinel `Pointer(Void)`
# (prelude hello: `Slice(typeof(deque.buffer.value))` in Deque.half_slices
# became `Slice(Pointer(::Void))`). A textual miss now falls back to
# expression inference.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-typeof_type_position_uncached_method.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > rolled_back_getter_result.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct Pointer(T)
  @[Primitive(:pointer_new)]
  def self.new(address : UInt64)
  end

  def self.null
    new 0_u64
  end

  @[Primitive(:pointer_add)]
  def +(offset : Int64) : self
  end

  @[Primitive(:pointer_get)]
  def value : T
  end
end

struct Sl(T)
  def initialize(@ptr : Pointer(T), @size : Int32)
  end

  def size
    @size
  end

  def to_unsafe
    @ptr
  end
end

class Dq(T)
  protected def buffer
    @buffer
  end

  def initialize(@size : Int32)
    @buffer = Pointer(T).null
  end

  def size
    @size
  end

  def self.halves(dq : Dq, &)
    yield Sl(typeof(dq.buffer.value)).new(dq.buffer + 0_i64, dq.size)
  end

  def total
    s = 0
    Dq.halves(self) do |sl|
      s = s &+ sl.size
    end
    s
  end
end


def g(d)
  d.size
end

def f8(n)
  d = Dq(Int32).new(n)
  g(d)
end

def f7(n)
  f8(n)
end

def f6(n)
  f7(n)
end

def f5(n)
  f6(n)
end

def f4(n)
  f5(n)
end

def f3(n)
  f4(n)
end

def f2(n)
  f3(n)
end

def f1(n)
  f2(n)
end

def late(n)
  Dq(Int32).new(n).total
end

LibC.exit(f1(28) &- 28 &+ late(28))
CR

cat > rolled_back_indirect_method_result.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct Pointer(T)
  @[Primitive(:pointer_new)]
  def self.new(address : UInt64)
  end

  def self.null
    new 0_u64
  end

  @[Primitive(:pointer_add)]
  def +(offset : Int64) : self
  end

  @[Primitive(:pointer_get)]
  def value : T
  end
end

struct Sl(T)
  def initialize(@ptr : Pointer(T), @size : Int32)
  end

  def size
    @size
  end

  def to_unsafe
    @ptr
  end
end

class Dq(T)
  def raw_buffer
    @buffer
  end

  protected def buffer
    raw_buffer
  end

  def initialize(@size : Int32)
    @buffer = Pointer(T).null
  end

  def size
    @size
  end

  def self.halves(dq : Dq, &)
    yield Sl(typeof(dq.buffer.value)).new(dq.buffer + 0_i64, dq.size)
  end

  def total
    s = 0
    Dq.halves(self) do |sl|
      s = s &+ sl.size
    end
    s
  end
end


def g(d)
  d.size
end

def f8(n)
  d = Dq(Int32).new(n)
  g(d)
end

def f7(n)
  f8(n)
end

def f6(n)
  f7(n)
end

def f5(n)
  f6(n)
end

def f4(n)
  f5(n)
end

def f3(n)
  f4(n)
end

def f2(n)
  f3(n)
end

def f1(n)
  f2(n)
end

def late(n)
  Dq(Int32).new(n).total
end

LibC.exit(f1(28) &- 28 &+ late(28))
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

check rolled_back_getter_result 28
check rolled_back_indirect_method_result 28

[[ $fail == 0 ]] || exit 1
printf 'PASS typeof_type_position_uncached_method\n'
