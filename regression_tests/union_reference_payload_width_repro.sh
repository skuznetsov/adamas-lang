#!/usr/bin/env bash
# Regression: a String member must not widen the LLVM layout of a mixed union.
#
# emit_union_type sized the payload from each variant's type-registry size.
# For heap-backed types that size is the instance size: register_class_types
# widens the shared builtin String type to 12 bytes, so `Int32 | String` was
# emitted as { i32, [2 x i64] } (24 bytes) while MIR field offsets and
# container strides use the 16-byte descriptor layout. Each union store wrote
# 8 bytes past its slot: Hash(String, Int32 | String) entries lost their hash
# (Entry#deleted? true, has_key? false, each empty) and a Pointer slot write
# clobbered the next slot's tag.
#
# A heap-backed variant (String, classes, arrays) now occupies one pointer
# word in the payload, matching the descriptor. A class member, which was
# already pointer-sized, is the control.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-union_reference_payload_width.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > pointer_slot_neighbour.cr <<'CR'
lib LibC
  fun exit(c : Int32) : NoReturn
end
class String
  @bytesize : Int32
  @length : Int32
  @c : UInt8
  def initialize
    @bytesize = 0
    @length = 0
    @c = 0_u8
  end
end
struct Pointer(T)
  @[Primitive(:pointer_malloc)]
  def self.malloc(size : UInt64) : self
  end
  @[Primitive(:pointer_add)]
  def +(offset : Int64) : self
  end
  @[Primitive(:pointer_set)]
  def value=(value : T) : T
  end
  @[Primitive(:pointer_get)]
  def value : T
  end
end
# Writing slot 0 after slot 1 must not clobber slot 1's tag.
p = Pointer(Int32 | String).malloc(3_u64)
(p + 1_i64).value = "m".as(Int32 | String)
p.value = 5.as(Int32 | String)
v = (p + 1_i64).value
LibC.exit(v.is_a?(String) ? 9 : 4)
CR

cat > struct_trailing_field.cr <<'CR'
lib LibC
  fun exit(c : Int32) : NoReturn
end
class String
  @bytesize : Int32
  @length : Int32
  @c : UInt8
  def initialize
    @bytesize = 0
    @length = 0
    @c = 0_u8
  end
end
struct Pointer(T)
  @[Primitive(:pointer_malloc)]
  def self.malloc(size : UInt64) : self
  end
  @[Primitive(:pointer_add)]
  def +(offset : Int64) : self
  end
  @[Primitive(:pointer_set)]
  def value=(value : T) : T
  end
  @[Primitive(:pointer_get)]
  def value : T
  end
end
# The union field must not overwrite the field declared after it. @hash is
# assigned first, so an over-wide union store lands on it afterwards.
struct E(V)
  @value : V
  @hash : UInt32
  def initialize(@hash : UInt32, @value : V)
  end
  def hash; @hash; end
end
e = E(Int32 | String).new(55_u32, 1)
LibC.exit(e.hash.to_i32!)
CR

cat > inline_entry_buffer.cr <<'CR'
lib LibC
  fun exit(c : Int32) : NoReturn
end
class String
  @bytesize : Int32
  @length : Int32
  @c : UInt8
  def initialize
    @bytesize = 0
    @length = 0
    @c = 0_u8
  end
end
struct Pointer(T)
  @[Primitive(:pointer_malloc)]
  def self.malloc(size : UInt64) : self
  end
  @[Primitive(:pointer_add)]
  def +(offset : Int64) : self
  end
  @[Primitive(:pointer_set)]
  def value=(value : T) : T
  end
  @[Primitive(:pointer_get)]
  def value : T
  end
end
# Hash::Entry shape in an inline buffer: the stored entry keeps its hash.
struct E(V)
  @key : String
  @value : V
  @hash : UInt32
  def initialize(@hash : UInt32, @key : String, @value : V)
  end
  def hash; @hash; end
end
p = Pointer(E(Int32 | String)).malloc(2_u64)
p.value = E(Int32 | String).new(55_u32, "a", 1)
LibC.exit(p.value.hash.to_i32!)
CR

cat > nilable_member.cr <<'CR'
lib LibC
  fun exit(c : Int32) : NoReturn
end
class String
  @bytesize : Int32
  @length : Int32
  @c : UInt8
  def initialize
    @bytesize = 0
    @length = 0
    @c = 0_u8
  end
end
struct Pointer(T)
  @[Primitive(:pointer_malloc)]
  def self.malloc(size : UInt64) : self
  end
  @[Primitive(:pointer_add)]
  def +(offset : Int64) : self
  end
  @[Primitive(:pointer_set)]
  def value=(value : T) : T
  end
  @[Primitive(:pointer_get)]
  def value : T
  end
end
# The same with a nilable member: Nil | Int32 | String was widened too.
struct E(V)
  @value : V
  @hash : UInt32
  def initialize(@hash : UInt32, @value : V)
  end
  def hash; @hash; end
end
e = E(Int32 | String | Nil).new(44_u32, nil)
LibC.exit(e.hash.to_i32!)
CR

cat > class_member_control.cr <<'CR'
lib LibC
  fun exit(c : Int32) : NoReturn
end
class String
  @bytesize : Int32
  @length : Int32
  @c : UInt8
  def initialize
    @bytesize = 0
    @length = 0
    @c = 0_u8
  end
end
struct Pointer(T)
  @[Primitive(:pointer_malloc)]
  def self.malloc(size : UInt64) : self
  end
  @[Primitive(:pointer_add)]
  def +(offset : Int64) : self
  end
  @[Primitive(:pointer_set)]
  def value=(value : T) : T
  end
  @[Primitive(:pointer_get)]
  def value : T
  end
end
# Control: a class member was already pointer-sized in the payload.
class Foo
  def initialize(@a : Int64, @b : Int64, @c : Int64)
  end
end
struct E(V)
  @value : V
  @tag : UInt32
  def initialize(@tag : UInt32, @value : V)
  end
  def tag; @tag; end
end
e = E(Int32 | Foo).new(66_u32, 1)
LibC.exit(e.tag.to_i32!)
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

check pointer_slot_neighbour 9
check struct_trailing_field 55
check inline_entry_buffer 55
check nilable_member 44
check class_member_control 66

[[ $fail == 0 ]] || exit 1
printf 'PASS union_reference_payload_width\n'
