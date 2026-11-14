#!/usr/bin/env bash
# Regression: a call on a closed union of concrete class/struct receivers whose
# arms declare different results (`J1#d : Int32`, `J0#d : Int64`) has the join
# of those results as its type, as in original Crystal.
#
# Only zero-argument calls on class unions joined the arm results. With
# arguments, or with a struct arm, the call took the result of the arm that
# anchored the dispatch name. `x = t1.d(3)` became Int64, `x.is_a?(Int32)`
# folded to false for the Int32 arm, and the struct dispatcher fed the Int32
# branch into an Int64 phi. Each arm now resolves its own source Def; the
# inline struct dispatcher wraps every branch result into the join.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-union_arm_source_result_join.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > struct_arms_int32_int64.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct J1
  def d(y : Int32) : Int32
    y &* 10
  end
end
struct J0
  def d(y : Int32) : Int64
    y.to_i64! &* 20_i64
  end
end
def lookup(u : Int64, t1 : J1 | J0) : Int32
  datetime1 = t1.d(3)
  datetime1.is_a?(Int32) ? 1 : 2
end
LibC.exit(lookup(50_i64, J0.new.as(J1 | J0)) &* 10 &+ lookup(50_i64, J1.new.as(J1 | J0)))
CR

cat > struct_arms_int32_bool.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct J1
  def d(y : Int32) : Int32
    y &* 10
  end
end
struct J0
  def d(y : Int32) : Bool
    y > 2
  end
end
def lookup(t1 : J1 | J0) : Int32
  x = t1.d(3)
  x.is_a?(Int32) ? x : (x ? 7 : 8)
end
LibC.exit(lookup(J0.new.as(J1 | J0)) &* 100 &+ lookup(J1.new.as(J1 | J0)))
CR

cat > class_arms_with_argument.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class C1
  def d(y : Int32) : Int32
    y &* 10
  end
end
class C0
  def d(y : Int32) : Int64
    y.to_i64! &* 20_i64
  end
end
def lookup(t1 : C1 | C0) : Int32
  x = t1.d(3)
  x.is_a?(Int32) ? 1 : 2
end
LibC.exit(lookup(C0.new.as(C1 | C0)) &* 10 &+ lookup(C1.new.as(C1 | C0)))
CR

cat > struct_arms_branch_values.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct J1
  def d(y : Int32) : Int32
    y &* 10
  end
end
struct J0
  def d(y : Int32) : Int64
    y.to_i64! &* 2_i64
  end
end
def lookup(t1 : J1 | J0) : Int32
  x = t1.d(3)
  if x.is_a?(Int32)
    x
  else
    x.to_i32! &+ 1
  end
end
LibC.exit(lookup(J0.new.as(J1 | J0)) &* 100 &+ lookup(J1.new.as(J1 | J0)))
CR

cat > struct_arms_zero_argument.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct C1
  def d : Int32
    30
  end
end
struct C0
  def d : Int64
    60_i64
  end
end
def lookup(t1 : C1 | C0) : Int32
  x = t1.d
  if x.is_a?(Int32)
    x
  else
    x.to_i32! &+ 1
  end
end
LibC.exit(lookup(C0.new.as(C1 | C0)) &+ lookup(C1.new.as(C1 | C0)))
CR

cat > class_arm_nilable_result.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class C1
  def d(y : Int32) : Int32?
    y > 5 ? nil : y
  end
end
class C0
  def d(y : Int32) : Int64
    y.to_i64!
  end
end
def kind(t : C1 | C0, y : Int32) : Int32
  x = t.d(y)
  x.is_a?(Nil) ? 5 : (x.is_a?(Int32) ? 1 : 2)
end
LibC.exit(kind(C1.new.as(C1 | C0), 9) &* 50 &+ kind(C1.new.as(C1 | C0), 3) &* 10 &+ kind(C0.new.as(C1 | C0), 3))
CR

cat > mixed_class_struct_three_arms.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class C1
  def d(y : Int32) : Int32
    y
  end
end
struct S0
  def d(y : Int32) : Int64
    y.to_i64! &* 2_i64
  end
end
struct S2
  def d(y : Int32) : Bool
    y > 2
  end
end
def kind(t : C1 | S0 | S2, y : Int32) : Int32
  x = t.d(y)
  if x.is_a?(Int32)
    x &+ 100
  elsif x.is_a?(Int64)
    x.to_i32! &+ 50
  else
    x ? 7 : 8
  end
end
LibC.exit(kind(C1.new.as(C1 | S0 | S2), 3) &+ kind(S0.new.as(C1 | S0 | S2), 3) &+ kind(S2.new.as(C1 | S0 | S2), 3))
CR

cat > arm_overload_by_argument_type.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct J1
  def d(y : Int32) : Int32
    y &* 10
  end

  def d(y : Bool) : Bool
    !y
  end
end
struct J0
  def d(y : Int32) : Int64
    y.to_i64! &* 20_i64
  end
end
def lookup(t1 : J1 | J0) : Int32
  x = t1.d(3)
  x.is_a?(Int32) ? 1 : 2
end
LibC.exit(lookup(J0.new.as(J1 | J0)) &* 10 &+ lookup(J1.new.as(J1 | J0)))
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

check struct_arms_int32_int64 21
check struct_arms_int32_bool 218
check class_arms_with_argument 21
check struct_arms_branch_values 218
check struct_arms_zero_argument 91
check class_arm_nilable_result 6
check mixed_class_struct_three_arms 166
check arm_overload_by_argument_type 21

[[ $fail == 0 ]] || exit 1
printf 'PASS union_arm_source_result_join\n'
