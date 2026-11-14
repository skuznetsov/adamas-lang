#!/usr/bin/env bash
# Regression: a block-taking class method called on a bare generic owner
# (`Pointer.malloc(size) { |i| yield i }`, `Cl.fill(1) { ... }`) binds the
# owner's formal from the block output, through the method's
# `& : Int32 -> T` restriction, as `Slice.new` already did for `new`.
#
# Only `new` was inferred. Other class methods borrowed whichever owner
# specialization the overload index had registered first, so
# `Pointer.malloc(size) { |i| yield i }` inside a Slice-like `new` lowered as
# `Pointer(En).malloc` for a `Pointer(En)` element ("expected Pointer(En)#value=
# value to be En, not Pointer(En)"), or failed with "can't infer the type
# parameter T for the generic class Pointer(T)".
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-generic_class_method_block_type_arg.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > slice_like_new_nested_malloc.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct Int32
  def times(&)
    i = 0
    while i < self
      yield i
      i &+= 1
    end
  end
end

struct Pointer(T)
  @[Primitive(:pointer_malloc)]
  def self.malloc(size : UInt64) : self
  end

  @[Primitive(:pointer_set)]
  def value=(value : T) : T
  end

  @[Primitive(:pointer_get)]
  def value : T
  end

  def self.malloc(size : Int32, & : Int32 -> T)
    ptr = Pointer(T).malloc(8_u64)
    size.times do |i|
      ptr.value = yield i
    end
    ptr
  end
end

struct Sl(T)
  def initialize(@pointer : Pointer(T), size : Int32, *, @read_only = false)
    @size = size
  end

  def self.new(size : Int32, *, read_only = false, &)
    pointer = Pointer.malloc(size) { |i| yield i }
    new(pointer, size, read_only: read_only)
  end

  def first
    @pointer.value
  end

  def size
    @size
  end
end

struct En
  @v = 7
  def v
    @v
  end
end

def mk : Pointer(En)
  Pointer(UInt8).malloc(64_u64).as(Pointer(En))
end

s = Sl(Pointer(En)).new(1) { mk }
LibC.exit(s.size &+ 5)
CR

cat > direct_malloc_block.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct Int32
  def times(&)
    i = 0
    while i < self
      yield i
      i &+= 1
    end
  end
end

struct Pointer(T)
  @[Primitive(:pointer_malloc)]
  def self.malloc(size : UInt64) : self
  end

  @[Primitive(:pointer_set)]
  def value=(value : T) : T
  end

  @[Primitive(:pointer_get)]
  def value : T
  end

  def self.malloc(size : Int32, & : Int32 -> T)
    ptr = Pointer(T).malloc(8_u64)
    size.times do |i|
      ptr.value = yield i
    end
    ptr
  end
end

struct Sl(T)
  def initialize(@pointer : Pointer(T), size : Int32, *, @read_only = false)
    @size = size
  end

  def self.new(size : Int32, *, read_only = false, &)
    pointer = Pointer.malloc(size) { |i| yield i }
    new(pointer, size, read_only: read_only)
  end

  def first
    @pointer.value
  end

  def size
    @size
  end
end

struct En
  @v = 7
end

p = Pointer.malloc(1) { |i| Pointer(UInt8).malloc(64_u64).as(Pointer(En)) }
LibC.exit(6)
CR

cat > malloc_through_yield_wrapper.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct Int32
  def times(&)
    i = 0
    while i < self
      yield i
      i &+= 1
    end
  end
end

struct Pointer(T)
  @[Primitive(:pointer_malloc)]
  def self.malloc(size : UInt64) : self
  end

  @[Primitive(:pointer_set)]
  def value=(value : T) : T
  end

  @[Primitive(:pointer_get)]
  def value : T
  end

  def self.malloc(size : Int32, & : Int32 -> T)
    ptr = Pointer(T).malloc(8_u64)
    size.times do |i|
      ptr.value = yield i
    end
    ptr
  end
end

struct Sl(T)
  def initialize(@pointer : Pointer(T), size : Int32, *, @read_only = false)
    @size = size
  end

  def self.new(size : Int32, *, read_only = false, &)
    pointer = Pointer.malloc(size) { |i| yield i }
    new(pointer, size, read_only: read_only)
  end

  def first
    @pointer.value
  end

  def size
    @size
  end
end

struct En
  @v = 7
end

def wrap(&)
  Pointer.malloc(1) { |i| yield i }
end

p = wrap { Pointer(UInt8).malloc(64_u64).as(Pointer(En)) }
LibC.exit(6)
CR

cat > malloc_scalar_block.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct Int32
  def times(&)
    i = 0
    while i < self
      yield i
      i &+= 1
    end
  end
end

struct Pointer(T)
  @[Primitive(:pointer_malloc)]
  def self.malloc(size : UInt64) : self
  end

  @[Primitive(:pointer_set)]
  def value=(value : T) : T
  end

  @[Primitive(:pointer_get)]
  def value : T
  end

  def self.malloc(size : Int32, & : Int32 -> T)
    ptr = Pointer(T).malloc(8_u64)
    size.times do |i|
      ptr.value = yield i
    end
    ptr
  end
end

struct Sl(T)
  def initialize(@pointer : Pointer(T), size : Int32, *, @read_only = false)
    @size = size
  end

  def self.new(size : Int32, *, read_only = false, &)
    pointer = Pointer.malloc(size) { |i| yield i }
    new(pointer, size, read_only: read_only)
  end

  def first
    @pointer.value
  end

  def size
    @size
  end
end

def wrap(&)
  Pointer.malloc(1) { |i| yield i }
end

p = wrap { 6 }
LibC.exit(p.value)
CR

cat > malloc_generic_struct_block.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct Int32
  def times(&)
    i = 0
    while i < self
      yield i
      i &+= 1
    end
  end
end

struct Pointer(T)
  @[Primitive(:pointer_malloc)]
  def self.malloc(size : UInt64) : self
  end

  @[Primitive(:pointer_set)]
  def value=(value : T) : T
  end

  @[Primitive(:pointer_get)]
  def value : T
  end

  def self.malloc(size : Int32, & : Int32 -> T)
    ptr = Pointer(T).malloc(8_u64)
    size.times do |i|
      ptr.value = yield i
    end
    ptr
  end
end

struct Sl(T)
  def initialize(@pointer : Pointer(T), size : Int32, *, @read_only = false)
    @size = size
  end

  def self.new(size : Int32, *, read_only = false, &)
    pointer = Pointer.malloc(size) { |i| yield i }
    new(pointer, size, read_only: read_only)
  end

  def first
    @pointer.value
  end

  def size
    @size
  end
end

struct Bx(U)
  def initialize(@u : U)
  end
  def u
    @u
  end
end

def wrap(&)
  Pointer.malloc(1) { |i| yield i }
end

p = wrap { Bx(Int32).new(6) }
LibC.exit(p.value.u)
CR

cat > user_generic_class_method.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct Int32
  def times(&)
    i = 0
    while i < self
      yield i
      i &+= 1
    end
  end
end

struct Pointer(T)
  @[Primitive(:pointer_malloc)]
  def self.malloc(size : UInt64) : self
  end

  @[Primitive(:pointer_set)]
  def value=(value : T) : T
  end

  @[Primitive(:pointer_get)]
  def value : T
  end

  def self.malloc(size : Int32, & : Int32 -> T)
    ptr = Pointer(T).malloc(8_u64)
    size.times do |i|
      ptr.value = yield i
    end
    ptr
  end
end

struct Sl(T)
  def initialize(@pointer : Pointer(T), size : Int32, *, @read_only = false)
    @size = size
  end

  def self.new(size : Int32, *, read_only = false, &)
    pointer = Pointer.malloc(size) { |i| yield i }
    new(pointer, size, read_only: read_only)
  end

  def first
    @pointer.value
  end

  def size
    @size
  end
end

struct Cl(T)
  def initialize(@v : T)
  end
  def v
    @v
  end
  def self.fill(size : Int32, & : Int32 -> T)
    Cl(T).new(yield 0)
  end
end

def wrap(&)
  Cl.fill(1) { |i| yield i }
end

p = wrap { Pointer(Int32).malloc(8_u64) }
p.v.value = 6
LibC.exit(p.v.value)
CR

cat > nested_generic_element_in_class.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct Int32
  def times(&)
    i = 0
    while i < self
      yield i
      i &+= 1
    end
  end
end

struct Pointer(T)
  @[Primitive(:pointer_malloc)]
  def self.malloc(size : UInt64) : self
  end

  @[Primitive(:pointer_set)]
  def value=(value : T) : T
  end

  @[Primitive(:pointer_get)]
  def value : T
  end

  def self.malloc(size : Int32, & : Int32 -> T)
    ptr = Pointer(T).malloc(8_u64)
    size.times do |i|
      ptr.value = yield i
    end
    ptr
  end
end

struct Sl(T)
  def initialize(@pointer : Pointer(T), size : Int32, *, @read_only = false)
    @size = size
  end

  def self.new(size : Int32, *, read_only = false, &)
    pointer = Pointer.malloc(size) { |i| yield i }
    new(pointer, size, read_only: read_only)
  end

  def first
    @pointer.value
  end

  def size
    @size
  end
end

class Ar(T, B)
  struct En(T)
    @v = 7

    def v
      @v
    end
  end

  @blocks : Sl(Pointer(En(T)))

  def initialize(@cap : Int32)
    @blocks = Sl(Pointer(En(T))).new(1) { allocate_block }
  end

  def size
    @blocks.size &+ B
  end

  private def allocate_block
    Pointer(UInt8).malloc(64_u64).as(Pointer(En(T)))
  end
end

class Pd
end

class Po
  @@arena : Ar(Pd, 5)?

  def self.arena
    @@arena ||= Ar(Pd, 5).new(4)
  end
end

LibC.exit(Po.arena.size)
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

check slice_like_new_nested_malloc 6
check direct_malloc_block 6
check malloc_through_yield_wrapper 6
check malloc_scalar_block 6
check malloc_generic_struct_block 6
check user_generic_class_method 6
check nested_generic_element_in_class 6

[[ $fail == 0 ]] || exit 1
printf 'PASS generic_class_method_block_type_arg\n'
