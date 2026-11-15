#!/usr/bin/env bash
# Regression: `case` arms must see assignments made by the subject and by
# the `when` conditions evaluated before them.
#
# lower_case snapshotted the locals before lowering the subject, and every arm
# and the else restarted from that snapshot. An assignment in the subject
# (`case (x = 7; x + 1)`) or in a `when` condition was dropped from every arm, from the later comparisons
# and from the join. The join base is now taken after the subject; each arm
# starts from the locals its comparison chain leaves, and the next comparison
# and the else continue from there. `case x = f(...)` and a yield subject
# are controls.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-case_subject_and_condition_locals.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > subject_assign_read_in_arm.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct Int32
  def ===(other : Int32) : Bool
    self == other
  end
end
x = 1
r = case (x = 7; x &+ 1)
    when 8 then x &* 2
    else 0
    end
LibC.exit((r &* 10 &+ x) & 255)
CR

cat > subject_assign_survives_unmatched_case.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct Int32
  def ===(other : Int32) : Bool
    self == other
  end
end
x = 1
case (x = 9; 3)
when 1 then x = 2
when 2 then x = 4
end
LibC.exit(x)
CR

cat > subject_assign_then_second_case.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct Int32
  def ===(other : Int32) : Bool
    self == other
  end
end
x = 1
y = case (x = 4; x)
    when 4 then 1
    when 5 then 2
    else 3
    end
case x
when 4 then y = y &+ 10
end
LibC.exit((x &* 20 &+ y) & 255)
CR

cat > subjectless_when_condition_assign_chain.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct Int32
  def ===(other : Int32) : Bool
    self == other
  end
end
x = 1
r = case
    when (x = 5; x == 6) then 1
    when (x = x &+ 2; x == 7) then x &* 3
    else 0
    end
LibC.exit((r &* 10 &+ x) & 255)
CR

cat > when_condition_assign_read_in_arm.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct Int32
  def ===(other : Int32) : Bool
    self == other
  end
end
x = 1
r = case 7
    when (x = 7) then x &+ 1
    else 0
    end
LibC.exit((r &* 10 &+ x) & 255)
CR

cat > when_condition_assign_reaches_else.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct Int32
  def ===(other : Int32) : Bool
    self == other
  end
end
x = 1
case 3
when (x = 4; 9) then x = 100
else x = x &+ 20
end
LibC.exit(x)
CR

cat > toplevel_loop_case_subject_assign.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct Int32
  def ===(other : Int32) : Bool
    self == other
  end
end
cnt = 0
n = 0
while n < 4
  case (cnt = cnt &* 10 &+ n &+ 1; n)
  when 1 then n &+= 1
  end
  n &+= 1
end
LibC.exit(cnt & 255)
CR

cat > case_yield_subject_control.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct Int32
  def ===(other : Int32) : Bool
    self == other
  end
end
def pr(&)
  case yield(3)
  when 1 then 10
  else 20
  end
end
acc = 1
r = pr { |v| acc = acc &* 10 &+ v; v }
LibC.exit((r &+ acc) & 255)
CR

cat > case_var_assign_subject_control.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct Int32
  def ===(other : Int32) : Bool
    self == other
  end
end
def f(a : Int32) : Int32
  a &+ 4
end
y = 0
case x = f(1)
when 5 then y = x &* 3
else y = 1
end
LibC.exit((y &* 10 &+ x) & 255)
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

check subject_assign_read_in_arm 147
check subject_assign_survives_unmatched_case 9
check subject_assign_then_second_case 91
check subjectless_when_condition_assign_chain 217
check when_condition_assign_read_in_arm 87
check when_condition_assign_reaches_else 24
check toplevel_loop_case_subject_assign 124
check case_yield_subject_control 33
check case_var_assign_subject_control 155

[[ $fail == 0 ]] || exit 1
printf 'PASS case_subject_and_condition_locals\n'
