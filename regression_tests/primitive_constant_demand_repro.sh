#!/usr/bin/env bash
# A constant initializer lowered from lower_main demands its call target
# eagerly, before lower_call reaches the numeric-primitive intrinsic. The
# body-less `@[Primitive(:binary)] def unsafe_div(other : Int32) : self` was
# then lowered as an ordinary source body and rejected by the source `self`
# return check ("must return UInt64 but it is returning Nil"); the full prelude
# hits this through Float::FastFloat MAX_MANTISSA. A body-less non-primitive
# `: self` def must still be rejected exactly as original Crystal does.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/primitive-constant-demand.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/constant_primitive.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct Int32
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end
struct UInt64
  @[::Primitive(:binary)]
  def unsafe_div(other : Int32) : self
  end

  @[::Primitive(:convert)]
  def to_i32! : Int32
  end
end
module M
  MAX = 100_u64.unsafe_div(5)
end
LibC.exit(M::MAX.to_i32!)
CR
POSITIVE_EXIT=20

cat > "$WORK_DIR/bodyless_plain_self.cr" <<'CR'
struct Int32
end
struct UInt64
  def plain_div(other : Int32) : self
  end
end
module M
  MAX = 100_u64.plain_div(5)
end
x = M::MAX
CR
NEGATIVE_DIAGNOSTIC="method UInt64#plain_div"
NEGATIVE_DIAGNOSTIC_TAIL="must return UInt64 but it is returning Nil"

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
      "$WORK_DIR/constant_primitive.cr" -o "$WORK_DIR/positive.orig" > "$WORK_DIR/positive.orig.log" 2>&1; then
    printf 'ORACLE FAIL: original rejects constant_primitive\n' >&2
    cat "$WORK_DIR/positive.orig.log" >&2
    exit 2
  fi
  "$SAFE_RUNNER" "$WORK_DIR/positive.orig" 5 256 > "$WORK_DIR/positive.orig.run" 2>&1 || true
  if [[ "$(exit_code_of "$WORK_DIR/positive.orig.run")" != "$POSITIVE_EXIT" ]]; then
    printf 'ORACLE FAIL: original constant_primitive did not exit %s\n' "$POSITIVE_EXIT" >&2
    exit 2
  fi
  if CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
      "$WORK_DIR/bodyless_plain_self.cr" -o "$WORK_DIR/negative.orig" > "$WORK_DIR/negative.orig.log" 2>&1 ||
      ! grep -qF "$NEGATIVE_DIAGNOSTIC_TAIL" "$WORK_DIR/negative.orig.log"; then
    printf 'ORACLE FAIL: original does not reject bodyless_plain_self\n' >&2
    exit 2
  fi
fi

failures=0

log="$WORK_DIR/positive.adamas.log"
"$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --prelude=empty "$WORK_DIR/constant_primitive.cr" \
  -o "$WORK_DIR/positive.adamas" > "$log" 2>&1 || true
if [[ "$(exit_code_of "$log")" != "0" ]]; then
  printf 'FAIL positive constant_primitive (compile): %s\n' "$(grep -m1 'error' "$log" || tail -1 "$log")"
  failures=$((failures + 1))
else
  run_log="$WORK_DIR/positive.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/positive.adamas" 5 256 > "$run_log" 2>&1 || true
  if [[ "$(exit_code_of "$run_log")" == "$POSITIVE_EXIT" ]]; then
    printf 'PASS positive constant_primitive\n'
  else
    printf 'FAIL positive constant_primitive (run): exit %s, expected %s\n' \
      "$(exit_code_of "$run_log")" "$POSITIVE_EXIT"
    failures=$((failures + 1))
  fi
fi

log="$WORK_DIR/negative.adamas.log"
"$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --prelude=empty "$WORK_DIR/bodyless_plain_self.cr" \
  -o "$WORK_DIR/negative.adamas" > "$log" 2>&1 || true
if [[ "$(exit_code_of "$log")" != "0" ]] && grep -qF "$NEGATIVE_DIAGNOSTIC" "$log" &&
    grep -qF "$NEGATIVE_DIAGNOSTIC_TAIL" "$log"; then
  printf 'PASS negative bodyless_plain_self\n'
else
  printf 'FAIL negative bodyless_plain_self: %s\n' "$(grep -m1 'error' "$log" || tail -1 "$log")"
  failures=$((failures + 1))
fi

if [[ "$failures" -ne 0 ]]; then
  printf '%d primitive constant-demand case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'primitive constant-demand cases passed\n'
