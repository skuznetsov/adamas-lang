#!/usr/bin/env bash
# Regression: an explicit `def self.new(value : UInt8)` reached through an
# integer literal autocast (`StaticArray(UInt8, 16).new(0)`, Crystal::MachO)
# must own the constructor call. The class-method resolver selected it by
# autocast, but the allocator only saw the raw [Int32] argument types, found
# no matching explicit `.new` and synthesized an [Int32] allocator against the
# zero-arg initializer (`completed initializer ABI disagrees with expanded
# allocator arguments`). Control: exact UInt8 arguments select the same
# explicit `.new` without autocast.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-explicit-new-literal-autocast.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > generic_static_array_literal.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct StaticArray(T, N)
  def self.new(& : Int32 -> T)
    array = uninitialized self
    i = 0
    while i < N
      (array.to_unsafe + i).value = yield i
      i &+= 1
    end
    array
  end

  def self.new(value : T)
    new { value }
  end

  private def initialize
  end

  def to_unsafe : Pointer(T)
    pointerof(@buffer)
  end
end

a = StaticArray(UInt8, 16).new(0)
b = StaticArray(UInt8, 4).new(7)
LibC.exit((a.to_unsafe + 15).value.to_i32! &+ (b.to_unsafe + 3).value.to_i32!)
CR

cat > struct_uninitialized_self_literal.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct Box
  @v : UInt8

  def self.new(value : UInt8)
    b = uninitialized self
    b.set(value)
    b
  end

  private def initialize
    @v = 0_u8
  end

  def set(v : UInt8)
    @v = v
  end

  def v : UInt8
    @v
  end
end

LibC.exit(Box.new(9).v.to_i32!)
CR

cat > class_delegating_new_literal.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class Box
  @v = 0

  def self.new(value : UInt8)
    new(value.to_i32! &+ 100, true)
  end

  def initialize(x : Int32, flag : Bool)
    @v = x
  end

  def v : Int32
    @v
  end
end

LibC.exit(Box.new(9).v)
CR

cat > control_exact_explicit_new.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct Box
  @v : UInt8

  def self.new(value : UInt8)
    b = uninitialized self
    b.set(value)
    b
  end

  private def initialize
    @v = 0_u8
  end

  def set(v : UInt8)
    @v = v
  end

  def v : UInt8
    @v
  end
end

x = 4_u8
LibC.exit(Box.new(x).v.to_i32! &+ Box.new(3_u8).v.to_i32!)
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

check generic_static_array_literal 7
check struct_uninitialized_self_literal 9
check class_delegating_new_literal 109
check control_exact_explicit_new 7

[[ $fail == 0 ]] || exit 1
printf 'PASS explicit new literal autocast\n'
