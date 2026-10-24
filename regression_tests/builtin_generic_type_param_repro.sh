#!/usr/bin/env bash
# A type parameter bound to a builtin generic instance (`T` =
# `Tuple(UInt64, UInt64, UInt64)`) is a type even before any value of that
# instance has registered it. Its identifier resolution accepted only
# registered types and source generic templates, so `T.to_s` in
# `Pointer(T)#to_s` raised "undefined constant T" on prelude hello. A genuinely
# undefined constant in such a body must still be rejected.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/builtin-generic-type-param.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

PRELUDE='lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

struct Int32
  @[Primitive(:binary)]
  def &+(other : Int32) : self
  end
end

struct Tuple
  def self.sz : Int32
    3
  end
end

struct UInt64
  def self.sz : Int32
    8
  end
end

struct Pointer(T)
  @[Primitive(:pointer_new)]
  def self.new(address : UInt64)
  end

  def self.null
    new 0_u64
  end

  def m : Int32
    T.sz &+ 1
  end

  def bad : Int32
    U.sz
  end
end'

write_case() {
  printf '%s\n%s\n' "$PRELUDE" "$2" > "$WORK_DIR/$1.cr"
}

write_case tuple_bound_param '
LibC.exit(Pointer(Tuple(UInt64, UInt64, UInt64)).null.m)'

write_case single_tuple_bound_param '
LibC.exit(Pointer(Tuple(UInt64)).null.m)'

write_case scalar_bound_param '
LibC.exit(Pointer(UInt64).null.m)'

write_case undefined_constant '
LibC.exit(Pointer(Tuple(UInt64)).null.bad)'

POSITIVE_CASES=(tuple_bound_param:4 single_tuple_bound_param:4 scalar_bound_param:9)
NEGATIVE_CASE=undefined_constant
ORACLE_DIAGNOSTIC="undefined constant U"
NEGATIVE_DIAGNOSTIC="undefined constant U"

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for entry in "${POSITIVE_CASES[@]}"; do
    name="${entry%%:*}"
    expected="${entry##*:}"
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if [[ "$(exit_code_of "$WORK_DIR/$name.orig.run")" != "$expected" ]]; then
      printf 'ORACLE FAIL: original %s did not exit %s\n' "$name" "$expected" >&2
      exit 2
    fi
  done
  if CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
      "$WORK_DIR/$NEGATIVE_CASE.cr" -o "$WORK_DIR/$NEGATIVE_CASE.orig" > "$WORK_DIR/$NEGATIVE_CASE.orig.log" 2>&1 ||
      ! grep -qF "$ORACLE_DIAGNOSTIC" "$WORK_DIR/$NEGATIVE_CASE.orig.log"; then
    printf 'ORACLE FAIL: original does not reject %s\n' "$NEGATIVE_CASE" >&2
    cat "$WORK_DIR/$NEGATIVE_CASE.orig.log" >&2
    exit 2
  fi
fi

failures=0

for entry in "${POSITIVE_CASES[@]}"; do
  name="${entry%%:*}"
  expected="${entry##*:}"
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --prelude=empty "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL positive %s (compile exit %s): %s\n' "$name" "$(exit_code_of "$log")" \
      "$(grep -m1 -i 'error\|invalid memory' "$log" || tail -1 "$log")"
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  if [[ "$(exit_code_of "$run_log")" == "$expected" ]]; then
    printf 'PASS positive %s\n' "$name"
  else
    printf 'FAIL positive %s (run): exit %s, expected %s\n' "$name" "$(exit_code_of "$run_log")" "$expected"
    failures=$((failures + 1))
  fi
done

log="$WORK_DIR/$NEGATIVE_CASE.adamas.log"
"$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --prelude=empty "$WORK_DIR/$NEGATIVE_CASE.cr" \
  -o "$WORK_DIR/$NEGATIVE_CASE.adamas" > "$log" 2>&1 || true
if [[ "$(exit_code_of "$log")" == "1" ]] && grep -qF "$NEGATIVE_DIAGNOSTIC" "$log" &&
    [[ ! -e "$WORK_DIR/$NEGATIVE_CASE.adamas" ]]; then
  printf 'PASS negative %s\n' "$NEGATIVE_CASE"
else
  printf 'FAIL negative %s (exit %s): %s\n' "$NEGATIVE_CASE" "$(exit_code_of "$log")" \
    "$(grep -m1 -i 'error' "$log" || tail -1 "$log")"
  failures=$((failures + 1))
fi

if [[ "$failures" -ne 0 ]]; then
  printf '%d builtin-generic type-parameter case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'builtin-generic type-parameter cases passed\n'
