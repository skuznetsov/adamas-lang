#!/usr/bin/env bash
# Regression: a yield in a `case` subject or `when` condition makes the def a
# yielding def.
#
# The yield scanner looked only at the `when`/`else` bodies of a CaseNode, so
# `def pr(&); case yield(1) ... end; end` was not seen as yielding. The def was
# then lowered as a standalone function, its yield got a Void value and every
# `when` comparison failed. The scanner now also visits the subject, the
# `when`/`in` conditions and the `in` bodies, which replaces the separate deep
# scan that block-to-proc lowering used for the same positions. A yield in
# a `when` condition with a subject and a `case v = yield e` inside a nested
# block are controls.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-case_yield_subject_scan.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > case_yield_subject_then_local.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct Int32
  def ===(other : Int32) : Bool
    self == other
  end
end
def pr(&)
  n = 0
  case yield(1)
  when 1 then n &+= 5
  end
  n
end
LibC.exit(pr { |v| v })
CR

cat > assigned_case_yield_subject.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct Int32
  def ===(other : Int32) : Bool
    self == other
  end
end
def pr(&)
  r = case yield(1)
      when 1 then 7
      else 9
      end
  r
end
LibC.exit(pr { |v| v })
CR

cat > loop_case_yield_subject_accumulates.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct Int32
  def ===(other : Int32) : Bool
    self == other
  end
end
def pr(fmt : Int32, &)
  n = 0
  s = 0
  while n < fmt
    case yield(n)
    when 1 then s &+= 10
    end
    n &+= 1
  end
  s
end
LibC.exit(pr(4) { |v| v })
CR

cat > loop_case_yield_subject_with_capture.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct Int32
  def ===(other : Int32) : Bool
    self == other
  end
end
def pr(fmt : Int32, &)
  n = 0
  c = 0
  while n < fmt
    case yield(n)
    when 1 then n &+= 1
    end
    c &+= 1
    n &+= 1
  end
  c
end
acc = 0
LibC.exit(pr(4) { |v| acc = acc &+ 1; v })
CR

cat > loop_case_yield_subject_block_writes_caller.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct Int32
  def ===(other : Int32) : Bool
    self == other
  end
end
def pr(fmt : Int32, &)
  n = 0
  while n < fmt
    case yield(n)
    when 1 then n &+= 1
    end
    n &+= 1
  end
end
acc = 0
pr(4) { |v| acc = acc &* 10 &+ v &+ 1; v }
LibC.exit(acc & 255)
CR

cat > subjectless_when_yield_condition.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct Int32
  def ===(other : Int32) : Bool
    self == other
  end
end
def pr(&)
  r = 0
  case
  when yield(3) == 3 then r = 11
  else r = 22
  end
  r
end
LibC.exit(pr { |v| v })
CR

cat > loop_case_yield_subject_control.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct Int32
  def ===(other : Int32) : Bool
    self == other
  end
end
def pr(fmt : Int32, &)
  n = 0
  while n < fmt
    case yield(n)
    when 1 then n &+= 1
    end
    n &+= 1
  end
  n
end
LibC.exit(pr(4) { |v| v })
CR

cat > when_yield_condition_control.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct Int32
  def ===(other : Int32) : Bool
    self == other
  end
end
def pr(x : Int32, &)
  case x
  when yield(1) then 40
  when yield(2) then 50
  else 60
  end
end
LibC.exit(pr(4) { |v| v &* 2 })
CR

cat > nested_block_case_yield_assign_control.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct Int32
  def ===(other : Int32) : Bool
    self == other
  end
end
def each3(&)
  yield 1
  yield 2
  yield 3
end
def fm(&)
  s = 0
  each3 do |e|
    case v = yield e
    when 4 then s &+= 100
    else s &+= v
    end
  end
  s
end
LibC.exit(fm { |e| e &* 2 })
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

check case_yield_subject_then_local 5
check assigned_case_yield_subject 7
check loop_case_yield_subject_accumulates 10
check loop_case_yield_subject_with_capture 3
check loop_case_yield_subject_block_writes_caller 124
check subjectless_when_yield_condition 11
check loop_case_yield_subject_control 4
check when_yield_condition_control 50
check nested_block_case_yield_assign_control 108

[[ $fail == 0 ]] || exit 1
printf 'PASS case_yield_subject_scan\n'
