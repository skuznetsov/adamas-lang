#!/usr/bin/env bash
# Regression: `until` loops must carry inlined yield blocks' caller-local
# writes like `while` loops do.
#
# lower_until was a separate, older copy of lower_while. It never learned the
# inline yield machinery (yield-origin assigned vars, caller-frame shadow phis,
# back-edge values for loop variables written by a yielded block, the
# caller-frame join at the exit), so a block writing a caller local inside a
# callee `until` loop lost the write. `until c` now lowers through lower_while
# with the condition's branch targets swapped. Plain `until`, break with a
# value, next and a single-loop yield are controls.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-until_inline_yield_caller_locals.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > until_then_nested_until_yield.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  while n < fmt
    k = 0
    until k == 2
      yield k
      k &+= 1
    end
    n &+= 1
  end
end
acc = 0
pr(2) { |v| acc = acc &* 3 &+ v &+ 1 }
LibC.exit(acc & 255)
CR

cat > conditional_yield_then_second_until.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  until n == fmt
    if n == 1
      yield 5
    end
    n &+= 1
  end
  m = 0
  until m == 2
    yield m
    m &+= 1
  end
end
acc = 0
pr(3) { |v| acc = acc &* 10 &+ v &+ 1 }
LibC.exit(acc & 255)
CR

cat > until_yield_control.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  until n == fmt
    yield n
    n &+= 1
  end
end
acc = 0
pr(3) { |v| acc = acc &* 10 &+ v &+ 1 }
LibC.exit(acc & 255)
CR

cat > until_break_then_yield_control.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def pr(fmt : Int32, &)
  n = 0
  until n == 10
    yield n
    break if n == fmt
    n &+= 1
  end
  yield 7
end
acc = 0
pr(2) { |v| acc = acc &* 10 &+ v &+ 1 }
LibC.exit(acc & 255)
CR

cat > until_next_control.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
acc = 0
n = 0
until n == 4
  n &+= 1
  next if n == 2
  acc = acc &* 3 &+ n
end
LibC.exit(acc & 255)
CR

cat > until_break_value_control.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
n = 0
r = until n == 10
  n &+= 1
  break n &* 7 if n == 5
end
LibC.exit(r.nil? ? 1 : r)
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

check until_then_nested_until_yield 50
check conditional_yield_then_second_until 100
check until_yield_control 123
check until_break_then_yield_control 214
check until_next_control 22
check until_break_value_control 35

[[ $fail == 0 ]] || exit 1
printf 'PASS until_inline_yield_caller_locals\n'
