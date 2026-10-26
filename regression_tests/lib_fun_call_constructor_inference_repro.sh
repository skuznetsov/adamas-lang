#!/usr/bin/env bash
# Generic `.new` infers its type arguments from the initializer restrictions
# (`@p : Pointer(T)`) by asking `infer_type_from_expr` for each argument's
# type. That inference had no answer for a lib fun call, so an argument
# written as `LibX.fun(...)` bound nothing. Without the prelude this raised
# "cannot infer Sl type arguments"; with the prelude, stage 2 failed in
# regex/pcre2.cr with "no overload matches Slice(UInt8).new for argument
# types (Pointer(UInt64), UInt32)" at `Slice.new(LibPCRE2.get_ovector_pointer(md), n)`.
# A lib call whose return type contradicts the restriction must stay rejected.
# Positive cases exit 42 under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lib-fun-ctor-infer.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

write_case() {
  local name="$1" body="$2"
  {
    cat <<'HEAD'
lib LibC
  alias SizeT = UInt64
  fun exit(status : Int32) : NoReturn
  fun malloc(n : SizeT) : SizeT*
  fun abs(x : Int32) : Int32
end

lib LibW
  fun words = malloc(n : UInt64) : UInt64*
end

lib LibB
  fun bytes = calloc(count : UInt64, size : UInt64) : UInt8*
end

struct Pair(T)
  def initialize(@a : Pointer(T), @b : Pointer(T)); end

  def width
    sizeof(T)
  end
end

struct Sl(T)
  def initialize(@p : Pointer(T), n : Int32, *, @ro = false)
    @n = n
  end

  def n
    @n
  end

  def width
    sizeof(T)
  end
end

class Owner
  def make
    Sl.new(::LibC.malloc(64_u64), 2)
  end
end

HEAD
    printf '%s\n' "$body"
  } > "$WORK_DIR/$name.cr"
}

write_case alias_return "s = Sl.new(LibC.malloc(64_u64), 2); LibC.exit(s.width &* 5 &+ s.n)"
write_case direct_return "s = Sl.new(LibW.words(64_u64), 2); LibC.exit(s.width &* 5 &+ s.n)"
write_case named_flag "s = Sl.new(LibW.words(64_u64), 2, ro: true); LibC.exit(s.width &* 5 &+ s.n)"
write_case absolute_in_method "s = Owner.new.make; LibC.exit(s.width &* 5 &+ s.n)"
write_case two_lib_args "s = Pair.new(LibW.words(8_u64), LibC.malloc(8_u64)); LibC.exit(s.width &* 5 &+ 2)"
# Negative: the two lib results bind T to UInt64 and UInt8.
write_case conflicting_elements_rejected "s = Pair.new(LibW.words(8_u64), LibB.bytes(8_u64, 1_u64)); LibC.exit(s.width)"
# Negative: a non-pointer lib result cannot bind Pointer(T).
write_case non_pointer_rejected "s = Sl.new(LibC.abs(-2), 2); LibC.exit(s.n)"

POSITIVE=(alias_return direct_return named_flag absolute_in_method two_lib_args)
NEGATIVE=(conflicting_elements_rejected non_pointer_rejected)

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for name in "${POSITIVE[@]}"; do
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if [[ "$(exit_code_of "$WORK_DIR/$name.orig.run")" != "42" ]]; then
      printf 'ORACLE FAIL: original %s did not exit 42\n' "$name" >&2
      exit 2
    fi
  done
  for name in "${NEGATIVE[@]}"; do
    if CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original accepts %s\n' "$name" >&2
      exit 2
    fi
  done
fi

failures=0

for name in "${POSITIVE[@]}"; do
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL %s (compile exit %s): %s\n' "$name" "$(exit_code_of "$log")" \
      "$(grep -m1 -i 'error\|invalid memory' "$log" || tail -1 "$log")"
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  if [[ "$(exit_code_of "$run_log")" == "42" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s (run): exit %s, expected 42\n' "$name" "$(exit_code_of "$run_log")"
    failures=$((failures + 1))
  fi
done

for name in "${NEGATIVE[@]}"; do
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]] && grep -q "no overload matches\|cannot infer .* type arguments" "$log"; then
    printf 'PASS %s (rejected)\n' "$name"
  else
    printf 'FAIL %s: expected an overload or inference error\n' "$name"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d lib fun constructor inference case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'Lib fun constructor inference cases passed\n'
