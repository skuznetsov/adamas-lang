#!/usr/bin/env bash
# Regression: an enum literal returned from a method whose return type is a
# union containing the enum (`return Errno::B` from `Int32 | Errno`) must be
# wrapped in the enum's own union arm. Enum values travel in their Int32
# carrier, so return coercion picked the Int32 arm (`Int32 | Errno`) or no
# arm at all (`String | Errno`, `{Int32, Bool} | Errno`) and `is_a?(Errno)`
# was false. MIR then treated variant id 0 as unknown and re-matched the
# Int32 carrier, so the enum arm was lost again when the enum is the first
# variant (`Errno | Int32`). Controls: an Int32 returned into the same
# union stays in the Int32 arm; an `Errno.value` call result already carried
# the enum type.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-enum-literal-union-return.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > int_union_return_literal.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

enum Errno
  A
  B
end

def open(x : Int32) : Int32 | Errno
  return Errno::B if x <= 0
  x
end

s = open(-1)
LibC.exit(s.is_a?(Errno) ? 8 : 26)
CR

cat > string_union_return_literal.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

enum Errno
  A
  B
end

def open(x : Int32) : String | Errno
  return Errno::B if x <= 0
  "s"
end

s = open(-1)
LibC.exit(s.is_a?(Errno) ? 8 : 26)
CR

cat > string_union_implicit_literal.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

enum Errno
  A
  B
end

def open(x : Int32) : String | Errno
  Errno::B
end

s = open(-1)
LibC.exit(s.is_a?(Errno) ? 8 : 26)
CR

cat > string_union_return_local.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

enum Errno
  A
  B
end

def open(x : Int32) : String | Errno
  e = Errno::B
  return e if x <= 0
  "s"
end

s = open(-1)
LibC.exit(s.is_a?(Errno) ? 8 : 26)
CR

cat > tuple_union_return_literal.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

enum Errno
  A
  B

  def self.value : Errno
    Errno.new(1)
  end
end

def open(x : Int32) : {Int32, Bool} | Errno
  return Errno::B if x <= 0
  {x, true}
end

s = open(-1)
r = open(4)
a = s.is_a?(Errno) ? s.value : 9
b = r.is_a?(Errno) ? 9 : 4
LibC.exit(a &+ b &* 10)
CR

cat > control_int_arm.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

enum Errno
  A
  B

  def self.value : Errno
    Errno.new(1)
  end
end

def open(x : Int32) : Int32 | Errno
  return Errno::B if x <= 0
  x
end

r = open(5)
LibC.exit(r.is_a?(Int32) ? r : 26)
CR

cat > control_enum_call_result.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

enum Errno
  A
  B

  def self.value : Errno
    Errno.new(1)
  end
end

def open(x : Int32) : {Int32, Bool} | Errno
  return Errno.value if x <= 0
  {x, true}
end

s = open(-1)
LibC.exit(s.is_a?(Errno) ? 3 &+ s.value : 26)
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

check int_union_return_literal 8
check string_union_return_literal 8
check string_union_implicit_literal 8
check string_union_return_local 8
check tuple_union_return_literal 41
check control_int_arm 5
check control_enum_call_result 4

[[ $fail == 0 ]] || exit 1
printf 'PASS enum literal union return\n'
