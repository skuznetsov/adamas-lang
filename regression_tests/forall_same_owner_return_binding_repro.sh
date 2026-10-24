#!/usr/bin/env bash
# A method free variable in a return annotation that names the method's own
# generic owner (`def conv(x : U) : Bx(U) forall U` inside `class Bx(T)`) must
# resolve with U bound. annotation_type_ref binds the owner's receiver map
# (T only) in place of the active map, so `Bx(U)` resolved to the receiver
# type Bx(T); the call-site binder also recorded only bare `U` restrictions,
# not `U.class`. Prelude hello hits this in Slice(T)#unsafe_slice_of
# (`: Slice(U) forall U`), called from FileDescriptor.write_fully. The negative
# case checks that the bound return type is still checked against a later
# restriction.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/forall-same-owner-return.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/header.cr" <<'CR'
@[Link("gc", pkg_config: "bdw-gc")]
lib LibGC
end

lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end
CR

write_case() {
  local name="$1" body="$2"
  { cat "$WORK_DIR/header.cr"; printf '%s\n' "$body"; } > "$WORK_DIR/$name.cr"
}

write_case value_argument '
class Bx(T)
  def conv(x : U) : Bx(U) forall U
    Bx(U).new
  end
  def sz : Int32
    sizeof(T)
  end
end
LibC.exit(Bx(Int32).new.conv(1_u16).sz)'
write_case type_literal_argument '
class Bx(T)
  def conv(type : U.class) : Bx(U) forall U
    Bx(U).new
  end
  def sz : Int32
    sizeof(T)
  end
end
LibC.exit(Bx(Int32).new.conv(UInt16).sz)'
write_case return_passed_to_restriction '
class Bx(T)
  def initialize(@size : Int32)
  end
  def size
    @size
  end
  def conv(type : U.class) : Bx(U) forall U
    Bx(U).new(@size * 4)
  end
end
def ret(b : Bx(UInt8)) : Int32
  b.size
end
LibC.exit(ret(Bx(Int32).new(2).conv(UInt8)))'
write_case conflicting_restriction '
class Bx(T)
  def conv(type : U.class) : Bx(U) forall U
    Bx(U).new
  end
end
def ret(b : Bx(UInt16)) : Int32
  1
end
LibC.exit(ret(Bx(Int32).new.conv(UInt8)))'

POSITIVE_CASES=(value_argument:2 type_literal_argument:2 return_passed_to_restriction:8)
NEGATIVE_CASE=conflicting_restriction
NEGATIVE_ORACLE_DIAGNOSTIC="expected argument #1 to 'ret' to be Bx(UInt16), not Bx(UInt8)"
NEGATIVE_DIAGNOSTIC="no overload matches ret"

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
      ! grep -qF "$NEGATIVE_ORACLE_DIAGNOSTIC" "$WORK_DIR/$NEGATIVE_CASE.orig.log"; then
    printf 'ORACLE FAIL: original does not reject %s\n' "$NEGATIVE_CASE" >&2
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
  printf '%d forall same-owner return case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'forall same-owner return cases passed\n'
