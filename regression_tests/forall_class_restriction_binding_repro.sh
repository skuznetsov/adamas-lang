#!/usr/bin/env bash
# A `type : U.class` restriction binds the method free variable U from a type
# literal argument. Type literals carry their instance type through overload
# lookup (`X.class` restrictions resolve to the instance TypeRef too), but the
# free-variable binder only matched `U.class` against a `.class` name, so U
# stayed unbound and every call was rejected with "no overload matches".
# Prelude hello hits this in Crystal::System::FileDescriptor.write_fully
# (`Slice.new(pointer, size).unsafe_slice_of(UInt8)`). The negative case checks
# that a later restriction on the same free variable still rejects a conflict.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/forall-class-restriction.XXXXXX")"
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

write_case top_level_def '
def conv(type : U.class) : Int32 forall U
  sizeof(U)
end
LibC.exit(conv(UInt16))'
write_case generic_owner_instance_method '
class Bx(T)
  def conv(type : U.class) : Int32 forall U
    sizeof(U) + sizeof(T)
  end
end
b = Bx(Int32).new
LibC.exit(b.conv(UInt16))'
write_case free_variable_in_return_type '
class Bx(T)
  def sz : Int32
    sizeof(T)
  end
end
class Ow(T)
  def conv(type : U.class) : Bx(U) forall U
    Bx(U).new
  end
end
LibC.exit(Ow(Int32).new.conv(UInt64).sz)'
write_case conflicting_second_restriction '
def conv(type : U.class, x : U) : Int32 forall U
  sizeof(U)
end
LibC.exit(conv(UInt16, "s"))'

POSITIVE_CASES=(top_level_def:2 generic_owner_instance_method:6 free_variable_in_return_type:8)
NEGATIVE_CASE=conflicting_second_restriction
NEGATIVE_ORACLE_DIAGNOSTIC="expected argument #2 to 'conv' to be UInt16, not String"
NEGATIVE_DIAGNOSTIC="no overload matches conv"

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
  printf '%d forall class restriction case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'forall class restriction cases passed\n'
