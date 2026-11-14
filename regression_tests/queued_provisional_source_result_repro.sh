#!/usr/bin/env bash
# Regression: a consumer must not read the result of a producer whose real
# body is still owned by a queued force-lower continuation. With the retry
# driver active, `sub` suspended on a depth-refused `Str.new` (bypass cap) and
# its continuation was queued; `lchop?` then forced `sub` again through the
# exact-source result path. That second force had no replay recipe (the first
# consumed the pending callsite), so it completed a provisional body around
# the name-shaped `new` -> Pointer guess, and `lchop?` checked `Str?` against
# `Nil | Pointer` (prelude hello: `String#lchop?$Char must return Nil | String,
# but it is returning Nil | Pointer`, from `unsafe_byte_slice_string`).
# The sibling arity-3 `new` overload makes the family lookup foreign, so the
# guess is not repaired from the base return type. The cases differ in how
# deep the driver starts, so the shape is covered whichever force depth first
# refuses the producer.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-queued-provisional-source-result.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > direct_lchop.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
  fun malloc(size : UInt64) : Void*
end

class Str
  @bytesize = 0
  @length = 0

  def self.new(bytes : Int64, encoding : Int64, invalid : Int64? = nil) : Str
    new(LibC.malloc(8_u64).as(UInt8*))
  end

  def self.new(capacity, &)
    str = LibC.malloc((capacity &+ 16).to_u64!).as(UInt8*)
    bytesize, size = yield str
    str = str.as(Str)
    str.initialize_header(bytesize, size)
    str
  end

  def self.new(chars : UInt8*, bytesize, size = 0)
    new(bytesize) do |buffer|
      {bytesize.to_i32!, size.to_i32!}
    end
  end

  def self.new(chars : UInt8*)
    new(chars, 7_i64, 0_i64)
  end

  def initialize_header(@bytesize : Int32, @length : Int32 = 0)
  end

  def bytesize : Int32
    @bytesize
  end

  def to_unsafe : UInt8*
    pointerof(@length).as(UInt8*) + 4
  end

  protected def sub(byte_offset, count, size = 0)
    Str.new(to_unsafe, count, size)
  end

  def lchop?(prefix : Char) : Str?
    if @bytesize > 3
      sub(1, bytesize &- 1)
    end
  end
end

module CS
  def self.decode_frame(ip)
    decode_frame(ip) do |offset, symbol, file|
      symbol = Str.new(symbol)
      {offset, symbol, symbol}
    end
  end

  def self.decode_frame(ip, &)
    yield ip, LibC.malloc(64_u64).as(UInt8*), LibC.malloc(8_u64).as(UInt8*)
  end

  def self.decode_bt(ip) : Str?
    if frame = decode_frame(ip)
      _, function, file = frame
      function = function.lchop?('*')
    end
    function
  end
end

class Box
  def initialize(@a : Int32, @b : Int32)
  end

  def each(&)
    yield @a
    yield @b
  end

  def sum_map(&) : Int32
    s = 0
    each do |x|
      if v = yield x
        s &+= v.bytesize
      end
    end
    s
  end
end

r = Box.new(5, 6).sum_map { |ip| CS.decode_bt(ip) }
LibC.exit(r)
CR

cat > retry_loop_frame.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
  fun malloc(size : UInt64) : Void*
end

struct Pointer(T)
  def +(offset : Int32) : self
    Pointer(T).new(address &+ offset.to_u64!)
  end
end

class Str
  @bytesize = 0
  @length = 0

  def self.new(bytes : Int64, encoding : Int64, invalid : Int64? = nil) : Str
    new(LibC.malloc(8_u64).as(UInt8*))
  end

  def self.new(capacity, &)
    str = LibC.malloc((capacity &+ 16).to_u64!).as(UInt8*)
    bytesize, size = yield str
    str = str.as(Str)
    str.initialize_header(bytesize, size)
    str
  end

  def self.new(chars : UInt8*, bytesize, size = 0)
    return Str.new(0) { |b| {0, 0} } if bytesize == 0
    new(bytesize) do |buffer|
      {bytesize.to_i32!, size.to_i32!}
    end
  end

  def self.new(chars : UInt8*)
    new(chars, 7_i64, 0_i64)
  end

  def initialize_header(@bytesize : Int32, @length : Int32 = 0)
  end

  def bytesize : Int32
    @bytesize
  end

  def to_unsafe : UInt8*
    pointerof(@length).as(UInt8*) + 4
  end

  protected def sub(byte_offset, count, size = 0)
    Str.new(to_unsafe + byte_offset, count, size)
  end

  def starts_with?(c : Char) : Bool
    @bytesize > 3
  end

  def lchop?(prefix : Char | Int32) : Str?
    if starts_with?('*')
      sub(1, bytesize &- 1)
    end
  end

  def lchop(prefix : Char | Int32) : Str
    lchop?(prefix) || self
  end
end

module CS
  def self.dladdr(ip, &)
    yield ip, LibC.malloc(64_u64).as(UInt8*), LibC.malloc(8_u64).as(UInt8*)
  end

  def self.decode_frame(ip)
    decode_frame(ip) do |offset, symbol, file|
      symbol = symbol ? Str.new(symbol) : Str.new(LibC.malloc(8_u64).as(UInt8*))
      file = file ? Str.new(file) : Str.new(LibC.malloc(8_u64).as(UInt8*))
      {offset, symbol, file}
    end
  end

  def self.decode_frame(ip, &)
    original_ip = ip
    while true
      retry = dladdr(ip) do |file, symbol, address|
        offset = original_ip &- 1
        if offset == 0
          ip &-= 1
          true
        else
          return yield offset, symbol, address
        end
      end
      break unless retry
    end
  end

  def self.decode_function_name(pc) : Str?
    nil
  end

  def self.decode_bt(ip, full) : Str?
    if name = decode_function_name(ip)
      function = name
    elsif frame = decode_frame(ip)
      _, function, file = frame
      function = function.lchop('*')
    else
      function = Str.new(LibC.malloc(8_u64).as(UInt8*))
    end
    function
  end
end

class Box
  def initialize(@a : Int32, @b : Int32)
  end

  def each(&)
    yield @a
    yield @b
  end

  def sum_map(&) : Int32
    s = 0
    each do |x|
      if v = yield x
        s &+= v.bytesize
      end
    end
    s
  end
end

pre = Str.new(LibC.malloc(8_u64).as(UInt8*))
pre.to_unsafe
r = Box.new(5, 6).sum_map { |ip| CS.decode_bt(ip, false) }
LibC.exit(r)
CR

cat > nested_driver_start.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
  fun malloc(size : UInt64) : Void*
end

class Str
  @bytesize = 0
  @length = 0

  def self.new(bytes : Int64, encoding : Int64, invalid : Int64? = nil) : Str
    new(LibC.malloc(8_u64).as(UInt8*))
  end

  def self.new(capacity, &)
    str = LibC.malloc((capacity &+ 16).to_u64!).as(UInt8*)
    bytesize, size = yield str
    str = str.as(Str)
    str.initialize_header(bytesize, size)
    str
  end

  def self.new(chars : UInt8*, bytesize, size = 0)
    new(bytesize) do |buffer|
      {bytesize.to_i32!, size.to_i32!}
    end
  end

  def self.new(chars : UInt8*)
    new(chars, 7_i64, 0_i64)
  end

  def initialize_header(@bytesize : Int32, @length : Int32 = 0)
  end

  def bytesize : Int32
    @bytesize
  end

  def to_unsafe : UInt8*
    pointerof(@length).as(UInt8*) + 4
  end

  protected def sub(byte_offset, count, size = 0)
    Str.new(to_unsafe, count, size)
  end

  def lchop?(prefix : Char) : Str?
    if @bytesize > 3
      sub(1, bytesize &- 1)
    end
  end
end

module CS
  def self.decode_frame(ip)
    decode_frame(ip) do |offset, symbol, file|
      symbol = Str.new(symbol)
      {offset, symbol, symbol}
    end
  end

  def self.decode_frame(ip, &)
    yield ip, LibC.malloc(64_u64).as(UInt8*), LibC.malloc(8_u64).as(UInt8*)
  end

  def self.decode_bt(ip) : Str?
    if frame = decode_frame(ip)
      _, function, file = frame
      function = function.lchop?('*')
    end
    function
  end
end

class Box
  def initialize(@a : Int32, @b : Int32)
  end

  def each(&)
    yield @a
    yield @b
  end

  def sum_map(&) : Int32
    s = 0
    each do |x|
      if v = yield x
        s &+= v.bytesize
      end
    end
    s
  end
end

def go(ip)
  Box.new(ip, ip).sum_map { |x| CS.decode_bt(x) }
end
def go2(ip)
  go(ip) &+ 0
end
LibC.exit(go2(5) &+ 2)
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

check direct_lchop 12
check retry_loop_frame 12
check nested_driver_start 14

[[ $fail == 0 ]] || exit 1
printf 'PASS queued provisional source result\n'
