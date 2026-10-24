#!/usr/bin/env bash
# A union whose arms are modules that nothing includes holds type values, and
# a call on it dispatches to the arm's class-side method. Prelude hello hits
# this through Crystal::MachO#endianness, which returns
# IO::ByteFormat::LittleEndian | BigEndian into `format.decode(self, io)` in
# Int.from_io: the union call resolved to nothing and from_io was rejected as
# "returning Void" (an older build silently called the first arm).
# A union arm that lacks the method must still be rejected.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/module-value-union-dispatch.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/header.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

module Fmt
  abstract def decode(int : Int32.class, seed : Int32)

  module LE
    extend Fmt

    def self.decode(int : Int32.class, seed : Int32) : Int32
      seed
    end
  end

  module BE
    extend Fmt

    def self.decode(int : Int32.class, seed : Int32) : Int32
      4
    end
  end
end

struct Int32
  def self.from_seed(seed : Int32, format : Fmt) : self
    format.decode(self, seed)
  end
end

def pick(little : Bool)
  little ? Fmt::LE : Fmt::BE
end

module M
  def self.k : Int32
    3
  end
end

module N
  def self.k : Int32
    4
  end
end

def pick_mn(first : Bool)
  first ? M : N
end
CR

{ cat "$WORK_DIR/header.cr"; echo 'LibC.exit(Int32.from_seed(3, pick(true)))'; } > "$WORK_DIR/from_seed_little.cr"
{ cat "$WORK_DIR/header.cr"; echo 'LibC.exit(Int32.from_seed(3, pick(false)))'; } > "$WORK_DIR/from_seed_big.cr"
{ cat "$WORK_DIR/header.cr"; printf 'f = pick(false)\nLibC.exit(f.decode(Int32, 3))\n'; } > "$WORK_DIR/local_union_call.cr"
{ cat "$WORK_DIR/header.cr"; printf 'f = pick_mn(false)\nLibC.exit(f.k)\n'; } > "$WORK_DIR/zero_arg_member_call.cr"

cat > "$WORK_DIR/arm_without_method.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

module M
  def self.k : Int32
    3
  end
end

module N
end

def pick_mn(first : Bool)
  first ? M : N
end

f = pick_mn(false)
LibC.exit(f.k)
CR

POSITIVE_CASES=(from_seed_little:3 from_seed_big:4 local_union_call:4 zero_arg_member_call:4)
NEGATIVE_CASE=arm_without_method
NEGATIVE_DIAGNOSTIC="undefined method 'k'"

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
      ! grep -qF "$NEGATIVE_DIAGNOSTIC" "$WORK_DIR/$NEGATIVE_CASE.orig.log"; then
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
  printf '%d module value union case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'module value union dispatch cases passed\n'
