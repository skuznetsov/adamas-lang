#!/usr/bin/env bash
# Regression: caller locals written by an inlined yield block must merge at
# ternary, `&&`, `||` and `case` joins.
#
# Yield blocks are inlined into the callee and keep the caller's locals on a
# side stack. `if`/`unless` snapshot that stack per arm and merge it at the
# join, but the dynamic ternary, short-circuit and case lowerings did not: a
# block write in one arm stayed visible after the join even when that arm was
# not taken (`f(2) { acc = 9 }` overwrote `acc` although `f` never yields
# for 2). The if/unless/elsif cases are controls.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-inline_yield_join_caller_locals.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > and_skipped_yield.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def f(x : Int32, &)
  x == 1 && yield 5
end
acc = 1
f(1) { |v| acc = acc &* 10 &+ v }
f(2) { |v| acc = 9 }
LibC.exit(acc)
CR

cat > or_skipped_yield.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def f(x : Int32, &)
  x == 1 || yield 5
end
acc = 1
f(2) { |v| acc = acc &* 10 &+ v }
f(1) { |v| acc = 9 }
LibC.exit(acc)
CR

cat > subjectless_case_two_whens.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def f(x : Int32, &)
  case
  when x == 1 then yield 5
  when x == 2 then yield 6
  end
end
acc = 1
f(1) { |v| acc = acc &* 10 &+ v }
f(3) { |v| acc = 9 }
f(2) { |v| acc = acc &* 10 &+ v }
LibC.exit(acc & 255)
CR

cat > if_control.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def f(x : Int32, &)
  if x == 1
    yield 5
  end
end
acc = 1
f(1) { |v| acc = acc &* 10 &+ v }
f(3) { |v| acc = 9 }
LibC.exit(acc)
CR

cat > ternary_one_yielding_arm.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def f(x : Int32, &)
  x == 1 ? yield(5) : 0
end
acc = 1
f(1) { |v| acc = acc &* 10 &+ v }
f(3) { |v| acc = 9 }
LibC.exit(acc)
CR

cat > case_subject_one_when.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct Int32
  def ===(other : Int32) : Bool
    self == other
  end
end
def f(x : Int32, &)
  case x
  when 1 then yield 5
  end
end
acc = 1
f(1) { |v| acc = acc &* 10 &+ v }
f(3) { |v| acc = 9 }
LibC.exit(acc)
CR

cat > unless_control.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def f(x : Int32, &)
  unless x == 1
    yield 5
  end
end
acc = 1
f(2) { |v| acc = acc &* 10 &+ v }
f(1) { |v| acc = 9 }
LibC.exit(acc)
CR

cat > if_elsif_control.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def f(x : Int32, &)
  if x == 1
    yield 5
  elsif x == 2
    yield 6
  end
end
acc = 1
f(1) { |v| acc = acc &* 10 &+ v }
f(3) { |v| acc = 9 }
f(2) { |v| acc = acc &* 10 &+ v }
LibC.exit(acc & 255)
CR

cat > ternary_both_arms_yield.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def f(x : Int32, &)
  x == 1 ? yield(5) : yield(6)
end
acc = 1
f(1) { |v| acc = acc &* 10 &+ v }
f(3) { |v| acc = acc &* 10 &+ v }
LibC.exit(acc & 255)
CR

cat > case_when_and_else_yield.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def f(x : Int32, &)
  case
  when x == 1 then yield 5
  else yield 6
  end
end
acc = 1
f(1) { |v| acc = acc &* 10 &+ v }
f(3) { |v| acc = acc &* 10 &+ v }
LibC.exit(acc & 255)
CR

cat > and_nested_block_yield.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def g(x : Int32, &)
  yield x
end
def f(x : Int32, &)
  x == 1 && g(x) { |w| yield w &+ 4 }
end
acc = 1
f(1) { |v| acc = acc &* 10 &+ v }
f(2) { |v| acc = 9 }
LibC.exit(acc)
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

check and_skipped_yield 15
check or_skipped_yield 15
check subjectless_case_two_whens 156
check if_control 15
check ternary_one_yielding_arm 15
check case_subject_one_when 15
check unless_control 15
check if_elsif_control 156
check ternary_both_arms_yield 156
check case_when_and_else_yield 156
check and_nested_block_yield 15

[[ $fail == 0 ]] || exit 1
printf 'PASS inline_yield_join_caller_locals\n'
