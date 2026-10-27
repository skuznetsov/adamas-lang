#!/usr/bin/env bash
# Integer literals autocast to a restricted parameter only when passed
# positionally. Passed by name they kept their default type, so
# `AdjustedMantissa.new(power2: 0, mantissa: 0)` (`@mantissa : UInt64`) failed
# with "no overload matches ... for argument types (Int32, Int32) and named
# arguments mantissa, power2". The prelude `"1.5".to_f64?` path
# (Float::FastFloat) stopped there. Named arguments now go through the same
# literal autocast as positional ones. The `reject_*` cases must still be
# compile errors: a negative literal into UInt64, an out-of-range UInt32
# literal into Int32, and a non-literal Int32 variable into UInt64.
# Each `run` case exits with its expected code under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/named-arg-autocast.XXXXXX")"

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
  def initialize(@mantissa : UInt64 = 0, @power2 : Int32 = 0)
  end

  def mantissa : UInt64
    @mantissa
  end

  def power2 : Int32
    @power2
  end
end

HEAD
    printf '%s\n' "$body"
  } > "$WORK_DIR/$name.cr"
}

# name:expected ("reject" means a compile error on both compilers)
CASES=()

add_case() {
  CASES+=("$1:$2")
  write_case "$1" "$3"
}

FINISH='LibC.exit(a.mantissa.to_i32! &+ a.power2 &+ 9)'

add_case all_named_literals 9 "a = AM.new(mantissa: 0, power2: 0)
$FINISH"

add_case one_named_literal 9 "a = AM.new(mantissa: 0)
$FINISH"

add_case named_nonzero_literals 211 "a = AM.new(mantissa: 200, power2: 2)
$FINISH"

add_case named_suffixed_literals 19 "a = AM.new(power2: 3_i8, mantissa: 7_u8)
$FINISH"

add_case named_literal_mixed_with_variable 53 "
def cf(w : UInt64) : AM
  if w == 0
    return AM.new(
      power2: 0,
      mantissa: 0,
    )
  end
  AM.new(power2: 3, mantissa: w)
end
a = cf(0_u64)
b = cf(5_u64)
LibC.exit(a.mantissa.to_i32! &+ a.power2 &+ b.mantissa.to_i32! &* 10 &+ b.power2)"

add_case generic_module_method 241 "
module Bf(T)
  def inf : Int32
    7
  end

  def cf(w : UInt64) : AM
    if w == 0
      return AM.new(
        power2: 0,
        mantissa: 0,
      )
    end
    if w > 100
      return AM.new(
        power2: inf,
        mantissa: 0,
      )
    end
    AM.new(power2: 3, mantissa: w)
  end
end

struct F
  include Bf(Float64)
end

a = F.new.cf(0_u64)
b = F.new.cf(5_u64)
c = F.new.cf(500_u64)
LibC.exit(a.mantissa.to_i32! &+ a.power2 &+ b.mantissa.to_i32! &* 10 &+ b.power2 &+ c.power2 &* 100)"

add_case reject_negative_literal reject "a = AM.new(mantissa: -1)
$FINISH"

add_case reject_out_of_range_literal reject "a = AM.new(power2: 3_000_000_000_u32)
$FINISH"

add_case reject_variable reject "m = 5
a = AM.new(power2: 1, mantissa: m)
$FINISH"

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for entry in "${CASES[@]}"; do
    name="${entry%%:*}" want="${entry##*:}"
    if CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      if [[ "$want" == "reject" ]]; then
        printf 'ORACLE FAIL: original accepts %s\n' "$name" >&2
        exit 2
      fi
    else
      if [[ "$want" == "reject" ]]; then
        continue
      fi
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
  if [[ "$want" == "reject" ]]; then
    if [[ "$(exit_code_of "$log")" == "0" ]]; then
      printf 'FAIL %s: compiled, expected a compile error\n' "$name" >&2
      failures=$((failures + 1))
    else
      printf 'PASS %s\n' "$name"
    fi
    continue
  fi
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
  printf '%d named argument autocast case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all named argument autocast cases passed\n'
