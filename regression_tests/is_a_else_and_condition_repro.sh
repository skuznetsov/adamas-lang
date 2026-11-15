#!/usr/bin/env bash
# Regression: the else branch of `if x.is_a?(T) && cond` narrowed `x` to
# `union - T`, so `x` read as Nil there even when `x` held an Int32 and only
# `cond` was false (wrong result, no diagnostic).
#
# The else branch inverted the then-branch target set, which unions the
# targets of both `&&` sides. A falsy `a && b` proves only `!a || !b`;
# original Crystal (TypeFilters.and joins negative filters with
# TypeFilter.or) keeps a target only when both sides carry the same one.
# A falsy `a || b` proves `!a && !b`, so either side's target holds there
# (`if x.is_a?(Nil) || y > 3 ... else x &+ 10`), which V2 rejected.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-is_a_else_and_condition.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > and_else_keeps_union.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def g(v : Int32) : Int32?
  v > 100 ? nil : v
end
def f(v : Int32, y : Int32) : Int32
  x = g(v)
  if x.is_a?(Int32) && y > 3
    1
  else
    x.is_a?(Int32) ? x &+ 10 : 7
  end
end
LibC.exit(f(5, 1) &* 3 &+ f(200, 9))
CR

cat > and_else_truthy_test.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def g(v : Int32) : Int32?
  v > 100 ? nil : v
end
def f(v : Int32, y : Int32) : Int32
  x = g(v)
  r = 0
  if x.is_a?(Int32) && y > 3
    r = 1
  else
    if x
      r = x &+ 20
    else
      r = 2
    end
  end
  r
end
LibC.exit(f(5, 1) &+ f(200, 9))
CR

cat > and_nil_target_else.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def g(v : Int32) : Int32?
  v > 100 ? nil : v
end
def f(v : Int32, y : Int32) : Int32
  x = g(v)
  if x.is_a?(Nil) && y > 3
    1
  else
    x.nil? ? 9 : 4
  end
end
LibC.exit(f(200, 1) &+ f(5, 9) &* 2)
CR

cat > grouped_and_else.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def g(v : Int32) : Int32?
  v > 100 ? nil : v
end
def f(v : Int32, y : Int32) : Int32
  x = g(v)
  if (x.is_a?(Int32) && y > 3)
    1
  else
    x.is_a?(Int32) ? x &+ 10 : 7
  end
end
LibC.exit(f(5, 1) &* 3 &+ f(200, 9))
CR

cat > and_two_vars_else.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def g(v : Int32) : Int32?
  v > 100 ? nil : v
end
def f(v : Int32, w : Int32) : Int32
  x = g(v)
  z = g(w)
  if x.is_a?(Nil) && z.is_a?(Nil)
    1
  else
    (x.nil? ? 2 : 4) &+ (z.nil? ? 20 : 40)
  end
end
LibC.exit(f(200, 5) &+ f(5, 200) &+ f(200, 200))
CR

cat > or_one_side_else_narrows.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def g(v : Int32) : Int32?
  v > 100 ? nil : v
end
def f(v : Int32, y : Int32) : Int32
  x = g(v)
  if x.is_a?(Nil) || y > 3
    1
  else
    x &+ 10
  end
end
LibC.exit(f(5, 1) &* 3 &+ f(200, 1) &+ f(5, 9))
CR

cat > unless_and_body.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def g(v : Int32) : Int32?
  v > 100 ? nil : v
end
def f(v : Int32, y : Int32) : Int32
  x = g(v)
  unless x.is_a?(Int32) && y > 3
    x.is_a?(Int32) ? x &+ 10 : 7
  else
    1
  end
end
LibC.exit(f(5, 1) &* 3 &+ f(200, 9))
CR

cat > and_with_elsif_else.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def g(v : Int32) : Int32?
  v > 100 ? nil : v
end
def f(v : Int32, y : Int32) : Int32
  x = g(v)
  if x.is_a?(Int32) && y > 3
    1
  elsif y > 100
    2
  else
    x.is_a?(Int32) ? x &+ 10 : 7
  end
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

check and_else_keeps_union 52
check and_else_truthy_test 27
check and_nil_target_else 17
check grouped_and_else 52
check and_two_vars_else 67
check or_one_side_else_narrows 47
check unless_and_body 52
check and_with_elsif_else 52

[[ $fail == 0 ]] || exit 1
printf 'PASS is_a_else_and_condition\n'
