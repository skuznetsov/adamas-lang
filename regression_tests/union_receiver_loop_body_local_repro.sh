#!/usr/bin/env bash
# Regression: a local first assigned inside a `while true` body from a call on
# a union receiver (`t1 : J1 | J0`) must get a loop-header phi typed by the
# union of the arms' declared results.
#
# AST-only inference looked the call up on the union name itself
# (`J0 | J1#d`), found nothing, and returned nil. lower_while skipped the
# body-only variable, so its post-loop binding became Void (prelude hello:
# `Time::TZ.lookup` must return `{Zone, {Int64, Int64}}` but returned
# `{Zone, {Nil | Int32 | Int64, ...}}`; reduced: "method lookup must return
# Int64, but it is returning Void"). Every arm now selects its own source Def;
# any arm without a declared result fails closed.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-union_receiver_loop_body_local.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > struct_union_loop_first_assign.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct J1
  def d(y : Int32) : Int64
    y.to_i64! &* 10_i64
  end
end

struct J0
  def d(y : Int32) : Int64
    y.to_i64! &* 20_i64
  end
end

def lookup(u : Int64, t1 : J1 | J0) : Int64
  year = 3
  while true
    datetime1 = t1.d(year)
    break if datetime1 > u
    year &+= 1
  end
  datetime1
end

LibC.exit(lookup(50_i64, J0.new.as(J1 | J0)).to_i32!)
CR

cat > tz_lookup_shape.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct J1
  def initialize(@time : Int32)
  end

  def time
    @time
  end

  def d(y : Int32) : Int64
    y.to_i64! &* 10_i64
  end
end

struct J0
  def initialize(@time : Int32)
  end

  def time
    @time
  end

  def d(y : Int32) : Int64
    y.to_i64! &* 20_i64
  end
end

alias Tr = J1 | J0

def lookup(u : Int64, a : Int32, b : Int32, t1 : Tr, t2 : Tr) : {Int32, {Int64, Int64}}
  if a == b
    is_dst = false
    range_begin = 0_i64
    range_end = 100_i64
  else
    std_offset = a
    dst_offset = b
    year = 3
    while true
      datetime1 = t1.d(year) &+ t1.time &+ std_offset
      datetime2 = t2.d(year) &+ t2.time &+ dst_offset
      break if datetime1 < u
      year &+= 1
    end
    if datetime2 < datetime1
      is_dst = true
      range_begin = t1.d(year &- 1) &+ t1.time
      range_end = datetime2
    else
      is_dst = false
      range_begin = datetime2
      range_end = datetime1
    end
  end
  {is_dst ? 1 : 2, {range_begin, range_end}}
end

r = lookup(50_i64, 1, 2, J1.new(1).as(Tr), J0.new(2).as(Tr))
LibC.exit((r[1][0] &+ r[1][1] &+ r[0]).to_i32!)
CR

cat > tz_lookup_shape_no_time.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct J1
  def initialize(@time : Int32)
  end

  def time
    @time
  end

  def d(y : Int32) : Int64
    y.to_i64! &* 10_i64
  end
end

struct J0
  def initialize(@time : Int32)
  end

  def time
    @time
  end

  def d(y : Int32) : Int64
    y.to_i64! &* 20_i64
  end
end

alias Tr = J1 | J0

def lookup(u : Int64, a : Int32, b : Int32, t1 : Tr, t2 : Tr) : {Int32, {Int64, Int64}}
  if a == b
    is_dst = false
    range_begin = 0_i64
    range_end = 100_i64
  else
    std_offset = a
    dst_offset = b
    year = 3
    while true
      datetime1 = t1.d(year) &+ std_offset
      datetime2 = t2.d(year) &+ dst_offset
      break if datetime1 < u
      year &+= 1
    end
    if datetime2 < datetime1
      is_dst = true
      range_begin = t1.d(year &- 1) 
      range_end = datetime2
    else
      is_dst = false
      range_begin = datetime2
      range_end = datetime1
    end
  end
  {is_dst ? 1 : 2, {range_begin, range_end}}
end

r = lookup(50_i64, 1, 2, J1.new(1).as(Tr), J0.new(2).as(Tr))
LibC.exit((r[1][0] &+ r[1][1] &+ r[0]).to_i32!)
CR

cat > tz_lookup_shape_no_dst.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct J1
  def initialize(@time : Int32)
  end

  def time
    @time
  end

  def d(y : Int32) : Int64
    y.to_i64! &* 10_i64
  end
end

struct J0
  def initialize(@time : Int32)
  end

  def time
    @time
  end

  def d(y : Int32) : Int64
    y.to_i64! &* 20_i64
  end
end

alias Tr = J1 | J0

def lookup(u : Int64, a : Int32, b : Int32, t1 : Tr, t2 : Tr) : {Int32, {Int64, Int64}}
  if a == b
    is_dst = false
    range_begin = 0_i64
    range_end = 100_i64
  else
    std_offset = a
    dst_offset = b
    year = 3
    while true
      datetime1 = t1.d(year) &+ t1.time
      datetime2 = t2.d(year) &+ t2.time
      break if datetime1 < u
      year &+= 1
    end
    if datetime2 < datetime1
      is_dst = true
      range_begin = t1.d(year &- 1) &+ t1.time
      range_end = datetime2
    else
      is_dst = false
      range_begin = datetime2
      range_end = datetime1
    end
  end
  {is_dst ? 1 : 2, {range_begin, range_end}}
end

r = lookup(50_i64, 1, 2, J1.new(1).as(Tr), J0.new(2).as(Tr))
LibC.exit((r[1][0] &+ r[1][1] &+ r[0]).to_i32!)
CR

cat > class_union_loop_first_assign.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class C1
  def d(y : Int32) : Int64
    y.to_i64! &* 10_i64
  end
end
class C0
  def d(y : Int32) : Int64
    y.to_i64! &* 20_i64
  end
end
def lookup(u : Int64, t1 : C1 | C0) : Int64
  year = 3
  while true
    datetime1 = t1.d(year)
    break if datetime1 > u
    year &+= 1
  end
  datetime1
end
LibC.exit((lookup(50_i64, C0.new.as(C1 | C0)) &+ lookup(50_i64, C1.new.as(C1 | C0))).to_i32!)
CR

cat > inherited_arm_binary_result.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
abstract struct B
  def d(y : Int32) : Int64
    y.to_i64! &* 10_i64
  end
end
struct J2 < B
end
struct J0
  def d(y : Int32) : Int64
    y.to_i64! &* 20_i64
  end
end
def lookup(u : Int64, t1 : J2 | J0) : Int64
  year = 3
  while true
    datetime1 = t1.d(year) &+ 1_i64
    break if datetime1 > u
    year &+= 1
  end
  datetime1
end
LibC.exit((lookup(50_i64, J0.new.as(J2 | J0)) &+ lookup(50_i64, J2.new.as(J2 | J0))).to_i32!)
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

check struct_union_loop_first_assign 60
check tz_lookup_shape 98
check tz_lookup_shape_no_time 95
check tz_lookup_shape_no_dst 95
check class_union_loop_first_assign 120
check inherited_arm_binary_result 112

[[ $fail == 0 ]] || exit 1
printf 'PASS union_receiver_loop_body_local\n'
