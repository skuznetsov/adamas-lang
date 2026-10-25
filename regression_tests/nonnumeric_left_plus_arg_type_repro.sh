#!/usr/bin/env bash
# Call-argument pre-inference typed `left + right` from the right operand
# whenever the left type name was not Int*/UInt*/Float*, even for a known
# non-numeric left. A slice local bound by `return unless dl = @dl` is still
# `Sl(UInt8) | Nil` there, so `dl + offset` was pre-typed Int32 and the call
# was rejected: prelude hello (1.22.1 stdlib) failed on
# `DWARF.line_sequence_at(debug_line + sequence_offset) do ... end`.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nonnumeric-left-plus-arg.XXXXXX")"
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

write_case narrowed_slice_block_arg '
struct Sl(T)
  def initialize(@pointer : Pointer(T), @size : Int32)
  end

  def +(offset : Int) : Sl(T)
    Sl(T).new(@pointer + offset, @size - offset)
  end

  def size : Int32
    @size
  end
end

struct Regs
  def initialize(@a : Int32)
  end

  def a : Int32
    @a
  end
end

module Dw
  def self.at(bytes : Sl(UInt8), & : Int32 ->) : Nil
    yield bytes.size
  end

  class Bt
    @dl : Sl(UInt8)?

    def dl=(v : Sl(UInt8)?)
      @dl = v
    end

    def initialize
      @dl = nil
      @ln = Pointer({Regs, Int32, Int32}).malloc(1_u64)
      @ln.value = {Regs.new(1), 2, 3}
    end

    def run(i, &) : Nil
      return unless dl = @dl
      regs, so, po = @ln.value
      Dw.at(dl + so) do |n|
        yield n + po
      end
    end
  end
end

b = Dw::Bt.new
b.dl = Sl(UInt8).new(Pointer(UInt8).malloc(10_u64), 10)
r = 0
b.run(0) { |n| r = n }
LibC.exit(r)
'
write_case narrowed_slice_arg '
struct Sl(T)
  def initialize(@pointer : Pointer(T), @size : Int32)
  end

  def +(offset : Int) : Sl(T)
    Sl(T).new(@pointer + offset, @size - offset)
  end

  def size : Int32
    @size
  end
end

struct Regs
  def initialize(@a : Int32)
  end

  def a : Int32
    @a
  end
end

module Dw
  def self.at(bytes : Sl(UInt8), & : Int32 ->) : Nil
    yield bytes.size
  end

  def self.at2(bytes : Sl(UInt8)) : Int32
    bytes.size
  end

  class Bt
    @dl : Sl(UInt8)?

    def dl=(v : Sl(UInt8)?)
      @dl = v
    end

    def initialize
      @dl = nil
      @ln = Pointer({Regs, Int32, Int32}).malloc(1_u64)
      @ln.value = {Regs.new(1), 2, 3}
    end

    def run(i, &) : Nil
      return unless dl = @dl
      regs, so, po = @ln.value
      n = Dw.at2(dl + so)
      yield n + po
    end
  end
end

b = Dw::Bt.new
b.dl = Sl(UInt8).new(Pointer(UInt8).malloc(10_u64), 10)
r = 0
b.run(0) { |n| r = n }
LibC.exit(r)
'

CASES=(narrowed_slice_block_arg:11 narrowed_slice_arg:11)

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for entry in "${CASES[@]}"; do
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
fi

failures=0

for entry in "${CASES[@]}"; do
  name="${entry%%:*}"
  expected="${entry##*:}"
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --prelude=empty "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL %s (compile exit %s): %s\n' "$name" "$(exit_code_of "$log")" \
      "$(grep -m1 -i 'error\|invalid memory' "$log" || tail -1 "$log")"
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  if [[ "$(exit_code_of "$run_log")" == "$expected" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s (run): exit %s, expected %s\n' "$name" "$(exit_code_of "$run_log")" "$expected"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d non-numeric left plus argument case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'non-numeric left plus argument cases passed\n'
