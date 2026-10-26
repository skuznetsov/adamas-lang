#!/usr/bin/env bash
# A primitive def (`@[Primitive(...)]`, no body) is lowered as an intrinsic at
# the call site. lower_call did that, but a no-parens call such as
# `exception.crystal_type_id` goes through member-access lowering, which
# emitted a plain call to the bodyless def. The backend then stubbed it, and
# prelude hello aborted in raise_without_backtrace with
# "STUB CALLED: Object$Hcrystal_type_id"; Symbol#to_i was stubbed the same
# way. Positive cases exit 42 under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/member-access-primitive.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

write_case() {
  local name="$1" body="$2"
  cat > "$WORK_DIR/$name.cr" <<'HEAD'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class Object
  @[Primitive(:object_crystal_type_id)]
  def crystal_type_id : Int32
  end
end

struct Symbol
  @[Primitive(:convert)]
  def to_i : Int32
  end
end

class Ex
end

class Sub < Ex
end

HEAD
  printf '%s\n' "$body" >> "$WORK_DIR/$name.cr"
}

write_case virtual_receiver 'def f(e : Ex) : Int32
  e.crystal_type_id
end

a = f(Sub.new)
b = f(Ex.new)
LibC.exit(a != b && a > 0 && b > 0 ? 42 : 3)'
write_case leaf_receiver 'a = Sub.new.crystal_type_id
b = Sub.new.crystal_type_id
LibC.exit(a == b && a > 0 ? 42 : 3)'
write_case symbol_to_i 'a = :alpha.to_i
b = :beta.to_i
LibC.exit(a != b && a == :alpha.to_i ? 42 : 3)'

POSITIVE=(virtual_receiver leaf_receiver symbol_to_i)

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
    printf 'FAIL %s (run exit %s)\n' "$name" "$(exit_code_of "$run_log")"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d case(s) failed\n' "$failures" >&2
  exit 1
fi
