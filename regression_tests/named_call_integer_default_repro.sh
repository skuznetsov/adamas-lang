#!/usr/bin/env bash
# A call with named arguments binds omitted parameters from their source
# defaults. An integer literal default is typed by its restriction when it
# fits, as original Crystal does and as positional calls already did, but the
# named path kept it Int32 and rejected the call ("no overload matches ...
# for bound argument types"); stdlib Crystal::DWARF::LineNumbers.new hits
# this through `@base_address : LibC::SizeT = 0`. A default that does not fit
# its restriction must still be rejected.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/named-call-integer-default.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# The class fixture allocates, so no-prelude fixtures link libgc.
PRELUDE='@[Link("gc", pkg_config: "bdw-gc")]
lib LibGC
end

lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

struct Int8
  @[Primitive(:convert)]
  def to_i32! : Int32
  end
end

struct UInt64
  @[Primitive(:convert)]
  def to_i32! : Int32
  end
end

struct Int32
  @[Primitive(:binary)]
  def &+(other : Int32) : self
  end
end
'

write_case() {
  printf '%s\n%s\n' "$PRELUDE" "$2" > "$WORK_DIR/$1.cr"
}

write_case ivar_default_with_named_tail '
class L
  def initialize(@io : Int32, size, @b : UInt64 = 0, @s : Int32? = nil)
  end

  def b : UInt64
    @b
  end
end

l = L.new(1, 2_u64, s: 3)
LibC.exit(l.b.to_i32! &+ 4)'

write_case unsigned_default_before_named_only '
def f(a : Int32, b : UInt64 = 0, *, c : Int32 = 1) : Int32
  b.to_i32! &+ c
end

LibC.exit(f(1, c: 6))'

write_case negative_signed_default '
def f(a : Int32, b : Int8 = -3, *, c : Int32 = 1) : Int32
  b.to_i32! &+ c
end

LibC.exit(f(1, c: 9))'

write_case positional_default '
def f(a : Int32, b : UInt64 = 0) : Int32
  b.to_i32! &+ a
end

LibC.exit(f(7))'

write_case unfit_default '
def f(a : Int32, b : UInt8 = 300, *, c : Int32 = 1) : Int32
  a
end

LibC.exit(f(1, c: 6))'

POSITIVE_CASES=(ivar_default_with_named_tail:4 unsigned_default_before_named_only:6 negative_signed_default:6 positional_default:7)
NEGATIVE_CASE=unfit_default
ORACLE_DIAGNOSTIC="can't restrict Int32 to UInt8"
NEGATIVE_DIAGNOSTIC="no overload matches f"

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
  printf '%d named-call integer-default case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'named-call integer-default cases passed\n'
