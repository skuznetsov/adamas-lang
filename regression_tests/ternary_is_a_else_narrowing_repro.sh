#!/usr/bin/env bash
# Regression: the else arm of a ternary did not see the condition's negative
# is_a? filters, so `x.is_a?(Nil) ? 5 : x` kept `x : Int32?` in the else arm
# ("must return Int32, but it is returning Int32 | Nil"). The `if/else`
# spelling and `x.nil? ? 5 : x` already narrowed.
#
# lower_ternary applied only falsy truthiness targets in the else arm;
# it now applies is_a_else_narrowing_targets like lower_if, on both the
# dynamic and the constant-condition path. Covers union struct receivers
# whose arms both return `Int32?`, `||`/`&&` conditions, nested arms, and a
# three-variant union that must stay unnarrowed.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-ternary_is_a_else_narrowing.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > nil_target_else_arm.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def g(v : Int32) : Int32?
  v > 100 ? nil : v
end
def f(v : Int32) : Int32
  x = g(v)
  x.is_a?(Nil) ? 5 : x
end
LibC.exit(f(200) &* 10 &+ f(3))
CR

cat > local_ternary_source.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct J1
  def d(y : Int32) : Int32?
    y > 5 ? nil : y
  end
end
def kind2(y : Int32) : Int32
  x = y > 5 ? nil : y
  x.is_a?(Nil) ? 5 : x
end
LibC.exit(kind2(3))
CR

cat > struct_union_arms_nilable.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct J1
  def d(y : Int32) : Int32?
    y > 5 ? nil : y
  end
end
struct J0
  def d(y : Int32) : Int32?
    y > 7 ? nil : y &+ 1
  end
end
def kind(t : J1 | J0, y : Int32) : Int32
  x = t.d(y)
  x.is_a?(Nil) ? 5 : x
end
LibC.exit(kind(J1.new.as(J1 | J0), 9) &* 10 &+ kind(J0.new.as(J1 | J0), 3))
CR

cat > or_condition_else_arm.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def g(v : Int32) : Int32?
  v > 100 ? nil : v
end
def h(v : Int32) : Int32 | Bool | Nil
  v > 100 ? nil : (v > 50 ? true : v)
end
def f(v : Int32, y : Int32) : Int32
  x = g(v)
  x.is_a?(Nil) || y > 3 ? 1 : x &+ 10
end
LibC.exit(f(5, 1) &* 3 &+ f(200, 1) &+ f(5, 9))
CR

cat > nested_else_arm.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def g(v : Int32) : Int32?
  v > 100 ? nil : v
end
def h(v : Int32) : Int32 | Bool | Nil
  v > 100 ? nil : (v > 50 ? true : v)
end
def f(v : Int32) : Int32
  x = g(v)
  x.is_a?(Nil) ? 5 : (x > 3 ? x : 0)
end
LibC.exit(f(200) &+ f(7) &* 2 &+ f(2))
CR

cat > three_variant_union_unnarrowed.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def g(v : Int32) : Int32?
  v > 100 ? nil : v
end
def h(v : Int32) : Int32 | Bool | Nil
  v > 100 ? nil : (v > 50 ? true : v)
end
def f(v : Int32) : Int32
  x = h(v)
  x.is_a?(Nil) ? 1 : (x.is_a?(Int32) ? x : 2)
end
LibC.exit(f(200) &+ f(60) &* 3 &+ f(9) &* 7)
CR

cat > specialized_param_static.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def g(v : Int32) : Int32?
  v > 100 ? nil : v
end
def h(v : Int32) : Int32 | Bool | Nil
  v > 100 ? nil : (v > 50 ? true : v)
end
def f(x : Int32?) : Int32
  x.is_a?(Nil) ? 5 : x
end
LibC.exit(f(4) &+ f(nil) &* 10)
CR

cat > ternary_value_assigned.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def g(v : Int32) : Int32?
  v > 100 ? nil : v
end
def h(v : Int32) : Int32 | Bool | Nil
  v > 100 ? nil : (v > 50 ? true : v)
end
def f(v : Int32) : Int32
  x = g(v)
  r = x.is_a?(Nil) ? 0 : x
  r &+ 1
end
LibC.exit(f(200) &+ f(6) &* 3)
CR

cat > and_condition_else_arm.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def g(v : Int32) : Int32?
  v > 100 ? nil : v
end
def h(v : Int32) : Int32 | Bool | Nil
  v > 100 ? nil : (v > 50 ? true : v)
end
def f(v : Int32, y : Int32) : Int32
  x = g(v)
  x.is_a?(Nil) && y > 3 ? 1 : (x.nil? ? 9 : 4)
end
LibC.exit(f(200, 1) &+ f(5, 9) &* 2)
CR

cat > and_condition_nested_is_a.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def g(v : Int32) : Int32?
  v > 100 ? nil : v
end
def f(v : Int32, y : Int32) : Int32
  x = g(v)
  x.is_a?(Int32) && y > 3 ? 1 : (x.is_a?(Int32) ? x &+ 10 : 7)
end
LibC.exit(f(5, 1) &* 3 &+ f(200, 9))
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

check nil_target_else_arm 53
check local_ternary_source 3
check struct_union_arms_nilable 54
check or_condition_else_arm 47
check nested_else_arm 19
check three_variant_union_unnarrowed 70
check specialized_param_static 54
check ternary_value_assigned 22
check and_condition_else_arm 17
check and_condition_nested_is_a 52

[[ $fail == 0 ]] || exit 1
printf 'PASS ternary_is_a_else_narrowing\n'
