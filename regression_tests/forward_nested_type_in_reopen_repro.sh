#!/usr/bin/env bash
# Crystal declares every type before typing any method, so a type nested in a
# later reopening is visible from an earlier one. io.cr declares
# `@decoder : Decoder?` and `@decoder ||= Decoder.new(encoding)` in `class IO`
# before io/encoding.cr reopens IO with `private class Decoder`. Adamas
# recorded a namespace's nested type names only when registration reached
# each reopening, so return-type inference run while registering the first
# `class Ion` resolved `Decoder` to a phantom top-level type: every prelude
# program failed with "undefined method 'gets' for Decoder" (io.cr:652), and
# a local `d = Decoder.new(30); d.val(5)` silently returned 0. A top-level
# type of the same name must not shadow the nested one, and an undeclared
# name stays rejected. Positive cases exit 42 under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/forward-nested-reopen.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

write_case() {
  local name="$1" owner_body="$2" main="$3"
  cat > "$WORK_DIR/$name.cr" <<CR
lib LibC
  fun exit(status : Int32) : NoReturn
end

class Ion
$owner_body
end

class Ion
  private class Decoder
    def initialize(@base : Int32)
    end

    def val(x : Int32)
      @base &+ x
    end

    def gets(io : Ion, delimiter : UInt8, limit : Int32, chomp : Bool) : Int32?
      @base &+ limit &+ (chomp ? 1 : 0)
    end
  end
end

$main
CR
}

# Shape of IO#decoder / IO#gets(Char, Int, chomp) in io.cr.
IO_SHAPE='  @decoder : Decoder?
  @enc : Int32? = 30

  private def decoder
    if enc = @enc
      @decoder ||= Decoder.new(enc)
    else
      nil
    end
  end

  def gets(delimiter : Char, limit : Int32, chomp = false) : Int32?
    decoder = decoder()
    if decoder
      return decoder.gets(self, 1_u8, limit: limit, chomp: chomp)
    end
    nil
  end'
IO_MAIN='r = Ion.new.gets('"'"'a'"'"', 11, chomp: true)
LibC.exit(r ? r : 0)'

LOCAL_SHAPE='  def run
    d = Decoder.new(30)
    d.val(5) &+ 7
  end'
LOCAL_MAIN='LibC.exit(Ion.new.run)'

TOP_DECODER='class Decoder
  def initialize(@base : Int32)
  end

  def val(x : Int32)
    0
  end
end'

write_case ivar_or_assign_call "$IO_SHAPE" "$IO_MAIN"
write_case local_typed_arg_call "$LOCAL_SHAPE" "$LOCAL_MAIN"
# A top-level type of the same name loses to the nested one.
write_case top_level_namesake "$LOCAL_SHAPE" "$TOP_DECODER
$LOCAL_MAIN"
# Negative: no reopening declares Missing.
write_case undeclared_rejected "${LOCAL_SHAPE//Decoder/Missing}" "$LOCAL_MAIN"

POSITIVE=(ivar_or_assign_call local_typed_arg_call top_level_namesake)
NEGATIVE=(undeclared_rejected)

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
    printf 'FAIL %s (run exit %s)\n' "$name" "$(exit_code_of "$run_log")"
    failures=$((failures + 1))
  fi
done

for name in "${NEGATIVE[@]}"; do
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" == "0" ]]; then
    printf 'FAIL %s (accepted)\n' "$name"
    failures=$((failures + 1))
  else
    printf 'PASS %s (rejected)\n' "$name"
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d case(s) failed\n' "$failures" >&2
  exit 1
fi
