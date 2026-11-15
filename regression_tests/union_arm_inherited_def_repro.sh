#!/usr/bin/env bash
# Regression: a union-receiver call whose arm only inherits the method
# (`class C1 < Base` with only `Base#d(y : Int32) : Int32`, receiver
# `C1 | C0` where `C0#d` returns Int64).
#
# The per-arm result query required a declaration on the concrete arm and
# otherwise gave up, so the call result fell back to one arm's type and the
# Int32 arm was converted to Int64 (`x.is_a?(Int32)` false, original 12 vs 22).
# A value-type arm also lost its abstract struct parent's Def, because the
# inheritance resolver names value-type targets after the requested owner.
# The arm now resolves the nearest class ancestor's annotated declaration
# against itself; included modules and generic ancestors fail closed.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-union_arm_inherited_def.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > class_parent_arm.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class Base
  def d(y : Int32) : Int32
    y
  end
end
class C1 < Base
end
class C0
  def d(y : Int32) : Int64
    y.to_i64! &* 2_i64
  end
end
def kind(t : C1 | C0) : Int32
  x = t.d(3)
  x.is_a?(Int32) ? 1 : 2
end
LibC.exit(kind(C1.new.as(C1 | C0)) &* 10 &+ kind(C0.new.as(C1 | C0)))
CR

cat > self_typed_inherited_result.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class Base
  def me : self
    self
  end
end
class C1 < Base
  def tag : Int32
    1
  end
end
class C0
  def me : self
    self
  end
  def tag : Int32
    2
  end
end
def kind(t : C1 | C0) : Int32
  t.me.tag
end
LibC.exit(kind(C1.new.as(C1 | C0)) &* 10 &+ kind(C0.new.as(C1 | C0)))
CR

cat > abstract_struct_parent_arm.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
abstract struct B
  def d(y : Int32) : Int32
    y
  end
end
struct S1 < B
end
struct S0
  def d(y : Int32) : Int64
    y.to_i64! &* 2_i64
  end
end
def kind(t : S1 | S0) : Int32
  x = t.d(3)
  x.is_a?(Int32) ? x : 9
end
LibC.exit(kind(S1.new.as(S1 | S0)) &* 10 &+ kind(S0.new.as(S1 | S0)))
CR

cat > module_supplied_arm_guard.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
module M
  def d(y : Int32) : Int32
    y &+ 1
  end
end
class C1
  include M
end
class C0
  def d(y : Int32) : Int64
    y.to_i64! &* 2_i64
  end
end
def kind(t : C1 | C0) : Int32
  x = t.d(3)
  x.is_a?(Int32) ? x : 7
end
LibC.exit(kind(C1.new.as(C1 | C0)) &* 10 &+ kind(C0.new.as(C1 | C0)))
CR

cat > multi_level_parent_arm.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class A
  def d(y : Int32) : Int32
    y
  end
end
class B < A
end
class C1 < B
end
class C0
  def d(y : Int32) : Int64
    y.to_i64! &* 2_i64
  end
end
def kind(t : C1 | C0) : Int32
  x = t.d(4)
  x.is_a?(Int32) ? x : 2
end
LibC.exit(kind(C1.new.as(C1 | C0)) &* 10 &+ kind(C0.new.as(C1 | C0)))
CR

cat > zero_arg_parent_arm.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class Base
  def d : Int32
    5
  end
end
class C1 < Base
end
class C0
  def d : Int64
    6_i64
  end
end
def kind(t : C1 | C0) : Int32
  x = t.d
  x.is_a?(Int32) ? x : 3
end
LibC.exit(kind(C1.new.as(C1 | C0)) &* 10 &+ kind(C0.new.as(C1 | C0)))
CR

cat > own_unannotated_arm_guard.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class C1
  def d(y : Int32)
    y
  end
end
class C0
  def d(y : Int32) : Int64
    y.to_i64! &* 2_i64
  end
end
def kind(t : C1 | C0) : Int32
  x = t.d(3)
  x.is_a?(Int32) ? 1 : 2
end
LibC.exit(kind(C1.new.as(C1 | C0)) &* 10 &+ kind(C0.new.as(C1 | C0)))
CR

cat > included_module_beats_parent_guard.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
module M
  def d(y : Int32) : Int32
    y &+ 5
  end
end
class Base
  def d(y : Int32) : Int64
    y.to_i64!
  end
end
class C1 < Base
  include M
end
class C0
  def d(y : Int32) : Int64
    y.to_i64! &* 2_i64
  end
end
def kind(t : C1 | C0) : Int32
  x = t.d(3)
  x.is_a?(Int32) ? x : 7
end
LibC.exit(kind(C1.new.as(C1 | C0)) &* 10 &+ kind(C0.new.as(C1 | C0)))
CR

cat > parent_overload_by_arg_type.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class Base
  def d(y : Int32) : Int32
    y
  end
  def d(y : Int64) : Int64
    y &* 3_i64
  end
end
class C1 < Base
end
class C0
  def d(y : Int32) : Int64
    y.to_i64! &* 2_i64
  end
end
def kind(t : C1 | C0) : Int32
  x = t.d(3)
  x.is_a?(Int32) ? x : 7
end
LibC.exit(kind(C1.new.as(C1 | C0)) &* 10 &+ kind(C0.new.as(C1 | C0)))
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

check class_parent_arm 12
check self_typed_inherited_result 12
check abstract_struct_parent_arm 39
check module_supplied_arm_guard 47
check multi_level_parent_arm 42
check zero_arg_parent_arm 53
check own_unannotated_arm_guard 12
check included_module_beats_parent_guard 87
check parent_overload_by_arg_type 37

[[ $fail == 0 ]] || exit 1
printf 'PASS union_arm_inherited_def\n'
