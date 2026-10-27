#!/usr/bin/env bash
# lower_call / member lowering / call-type repair typed any call named
# `round`, `abs`, `tdiv`, `clamp`, ... as returning its receiver, a guess meant
# for numeric methods whose return type is often unregistered. It overrode
# the callee's own contract: `def round(am : AM, &) : AM` on a user struct
# (called through a non-inlined block wrapper because of `return yield`)
# made `am_b = round(am) { ... }` a struct of the receiver type, and
# `to_float(false, am_b)` failed with "no overload matches ... (Bool, F64)".
# The prelude `"1.5".to_f64?` path stopped there (Float::FastFloat
# negative_digit_comp). A declared non-`self` return now wins, and the numeric
# names only describe numeric/union receivers. `*_control` cases cover the
# `: self` contracts that must still keep the (more precise) receiver type.
# Each case exits with its expected code under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/recv-preserving-return.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

write_case() {
  local name="$1" body="$2"
  {
    cat <<'HEAD'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct AM
  def initialize(@p : Int32)
  end

  def p : Int32
    @p
  end
end
HEAD
    printf '%s\n' "$body"
  } > "$WORK_DIR/$name.cr"
}

# name:expected-exit
CASES=()

add_case() {
  CASES+=("$1:$2")
  write_case "$1" "$3"
}

add_case block_wrapper_round 25 '
struct F64
  def round(am : AM, & : AM -> AM) : AM
    if am.p > 10
      return yield(am)
    end
    am
  end

  def to_float(am : AM) : Int32
    am.p
  end

  def neg(am : AM) : Int32
    am_b = round(am) do |a|
      AM.new(a.p &+ 1)
    end
    to_float(am_b)
  end
end

LibC.exit(F64.new.neg(AM.new(4)) &+ F64.new.neg(AM.new(20)))'

add_case included_module_round 14 '
module Bf(T, E)
  def round(am : AM, & : AM, Int32 -> AM) : AM
    if 0 &- am.p >= 10
      am = yield am, 1
      return AM.new(am.p &+ 26)
    end
    am = yield am, 3
    am
  end

  def round_down(am : AM, shift : Int32) : AM
    AM.new(am.p &+ shift)
  end

  def to_float(negative : Bool, am : AM) : Int32
    am.p &+ (negative ? 100 : 0)
  end

  def neg(am : AM) : Int32
    am_b = round(am) do |a, shift|
      round_down(a, shift)
    end
    to_float(false, am_b)
  end
end

struct F64
  include Bf(Float64, UInt64)
end

LibC.exit(F64.new.neg(AM.new(4)) &+ F64.new.neg(AM.new(-20)))'

add_case member_round_no_args 31 '
struct H
  def round : AM
    AM.new(31)
  end
end

LibC.exit(H.new.round.p)'

add_case abs_with_argument 41 '
struct H
  def abs(x : Int32) : AM
    AM.new(x &+ 1)
  end
end

LibC.exit(H.new.abs(40).p)'

add_case unannotated_struct_round 25 '
struct H
  def round(am : AM, &)
    if am.p > 10
      return yield(am)
    end
    am
  end

  def run(am : AM) : Int32
    r = round(am) { |a| AM.new(a.p &+ 1) }
    r.p
  end
end

LibC.exit(H.new.run(AM.new(4)) &+ H.new.run(AM.new(20)))'

add_case union_receiver_round 23 '
struct H1
  def round : AM
    AM.new(10)
  end
end

struct H2
  def round : AM
    AM.new(13)
  end
end

def pick(i : Int32) : H1 | H2
  i > 0 ? H1.new : H2.new
end

LibC.exit(pick(1).round.p &+ pick(0).round.p)'

add_case self_round_control 17 '
class A
  def round : self
    self
  end
end

class B < A
  def only_b : Int32
    17
  end
end

LibC.exit(B.new.round.only_b)'

add_case self_clamp_control 19 '
class A
  def clamp(x : Int32) : self
    self
  end
end

class B < A
  def only_b : Int32
    19
  end
end

LibC.exit(B.new.clamp(1).only_b)'

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for entry in "${CASES[@]}"; do
    name="${entry%%:*}" want="${entry##*:}"
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if [[ "$(exit_code_of "$WORK_DIR/$name.orig.run")" != "$want" ]]; then
      printf 'ORACLE FAIL: original %s exited %s, not %s\n' "$name" \
        "$(exit_code_of "$WORK_DIR/$name.orig.run")" "$want" >&2
      exit 2
    fi
  done
fi

failures=0

for entry in "${CASES[@]}"; do
  name="${entry%%:*}" want="${entry##*:}"
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL %s: compile failed\n' "$name" >&2
    grep -v '^\[RUN_SAFE' "$log" | grep -m3 -i 'error\|overload' >&2 || tail -5 "$log" >&2
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  got="$(exit_code_of "$run_log")"
  if [[ "$got" == "$want" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s: exit %s, expected %s\n' "$name" "$got" "$want" >&2
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d receiver-preserving return case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all receiver-preserving return cases passed\n'
