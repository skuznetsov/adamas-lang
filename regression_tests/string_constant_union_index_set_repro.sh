#!/usr/bin/env bash
# Regression: a String literal stored into a mixed-union array keeps its tag.
#
# `arr[i] = "lit"` lowers to an array_set whose value is the raw String; the
# backend wraps it into the element union and picks the discriminator from
# its value-type ledger. emit_constant recorded every string constant in that
# ledger as Pointer, so `Array(Int32 | String)#[]=` stored the Pointer type id
# and the element read back as neither String nor Int32. A String variable
# already carried its MIR type (control); a nilable array was only saved by
# the single-non-nil-arm fallback.
#
# String constants now keep their String type in the ledger.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-string_constant_union_index_set.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > literal_into_mixed_union_array.cr <<'CR'
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
class Array(T)
  @size : Int32
  @capacity : Int32
  @offset_to_buffer : Int32
  @buffer : Pointer(T)
  def initialize(@capacity : Int32)
    @size = 0
    @offset_to_buffer = 0
    @buffer = Pointer(T).malloc(@capacity.to_u64!)
  end
  def push(value : T)
    (@buffer + @size.to_i64!).value = value.as(T)
    @size = @size &+ 1
    self
  end
  def []=(index : Int32, value : T) : T
    (@buffer + index.to_i64!).value = value.as(T)
  end
  def [](index : Int32) : T
    (@buffer + index.to_i64!).value
  end
end
# A String literal stored into a mixed-union array keeps the String tag.
a = Array(Int32 | String).new(4)
a.push(2)
a[0] = "lit"
LibC.exit(a[0].is_a?(String) ? 7 : 3)
CR

cat > literal_beside_int_element.cr <<'CR'
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
class Array(T)
  @size : Int32
  @capacity : Int32
  @offset_to_buffer : Int32
  @buffer : Pointer(T)
  def initialize(@capacity : Int32)
    @size = 0
    @offset_to_buffer = 0
    @buffer = Pointer(T).malloc(@capacity.to_u64!)
  end
  def push(value : T)
    (@buffer + @size.to_i64!).value = value.as(T)
    @size = @size &+ 1
    self
  end
  def []=(index : Int32, value : T) : T
    (@buffer + index.to_i64!).value = value.as(T)
  end
  def [](index : Int32) : T
    (@buffer + index.to_i64!).value
  end
end
# The Int32 neighbour of a literal store keeps its own tag.
a = Array(Int32 | String).new(4)
a.push(2)
a.push(5)
a[1] = "lit"
LibC.exit(a[0].is_a?(Int32) && a[1].is_a?(String) ? 8 : 3)
CR

cat > string_variable_control.cr <<'CR'
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
class Array(T)
  @size : Int32
  @capacity : Int32
  @offset_to_buffer : Int32
  @buffer : Pointer(T)
  def initialize(@capacity : Int32)
    @size = 0
    @offset_to_buffer = 0
    @buffer = Pointer(T).malloc(@capacity.to_u64!)
  end
  def push(value : T)
    (@buffer + @size.to_i64!).value = value.as(T)
    @size = @size &+ 1
    self
  end
  def []=(index : Int32, value : T) : T
    (@buffer + index.to_i64!).value = value.as(T)
  end
  def [](index : Int32) : T
    (@buffer + index.to_i64!).value
  end
end
# Control: a String variable was already tagged from its MIR type.
def make : String
  "var"
end
a = Array(Int32 | String).new(4)
a.push(2)
s = make
a[0] = s
LibC.exit(a[0].is_a?(String) ? 6 : 3)
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

check literal_into_mixed_union_array 7
check literal_beside_int_element 8
check string_variable_control 6

[[ $fail == 0 ]] || exit 1
printf 'PASS string_constant_union_index_set\n'
