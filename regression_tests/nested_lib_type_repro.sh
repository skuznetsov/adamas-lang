#!/usr/bin/env bash
# A `lib` declared inside a class or module is the nested type Owner::LibName.
# The lib was never registered (only top-level libs reached register_lib), so
# 1.22.1's `@pointer.as(LibMachO::Header*)` in Crystal::System::MachO
# (crystal/system/unix/mach_o.cr) resolved to an unknown `LibMachO::Header`
# and `header.value.ncmds` was undefined.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nested-lib-type.XXXXXX")"
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

struct Int32
  @[Primitive(:binary)]
  def +(other : Int32) : Int32
  end
end

struct UInt32
  @[Primitive(:convert)]
  def to_i : Int32
  end
end

struct Pointer(T)
  @[Primitive(:pointer_malloc)]
  def self.malloc(size : UInt64)
  end

  @[Primitive(:pointer_get)]
  def value : T
  end

  @[Primitive(:pointer_set)]
  def value=(value : T)
  end
end
CR

{ cat "$WORK_DIR/header.cr"; cat <<'CR'; } > "$WORK_DIR/class_nested.cr"
class Crystal::System::MachO
  lib LibMachO
    struct Header
      ncmds : UInt32
      magic : UInt32
    end
  end

  def initialize(@pointer : Pointer(UInt8))
  end

  # Write through the first field's address: a lib-struct `ptr.value = v`
  # is a separate by-value store gap and stays out of this fixture.
  def store(n : UInt32) : Nil
    @pointer.as(UInt32*).value = n
  end

  def count : Int32
    each_cmd { |x| x }
  end

  private def each_cmd(&)
    yield header.value.ncmds.to_i
  end

  private def header
    @pointer.as(LibMachO::Header*)
  end
end

h = Pointer(Crystal::System::MachO::LibMachO::Header).malloc(1_u64)
m = Crystal::System::MachO.new(h.as(Pointer(UInt8)))
m.store(41_u32)
LibC.exit(m.count + 1)
CR

{ cat "$WORK_DIR/header.cr"; cat <<'CR'; } > "$WORK_DIR/module_nested.cr"
module Outer
  lib LibX
    alias Word = UInt32

    struct Pair
      a : Word
      b : Word
    end
  end

  def self.sum(p : LibX::Pair*) : Int32
    p.value.a.to_i + p.value.b.to_i
  end
end

p = Pointer(Outer::LibX::Pair).malloc(1_u64)
p.as(UInt32*).value = 42_u32
LibC.exit(Outer.sum(p))
CR

{ cat "$WORK_DIR/header.cr"; cat <<'CR'; } > "$WORK_DIR/module_nested_fun.cr"
module Outer2
  lib LibY
    fun exit(status : Int32) : NoReturn
  end

  def self.quit(code : Int32) : NoReturn
    LibY.exit(code)
  end
end

Outer2.quit(42)
CR

CASES=(
  "class_nested:42"
  "module_nested:42"
  "module_nested_fun:42"
)

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
  if [[ "$(exit_code_of "$run_log")" == "$expected" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s (run): exit %s, expected %s\n' "$name" "$(exit_code_of "$run_log")" "$expected"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d nested lib type case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'nested lib type cases passed\n'
