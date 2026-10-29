#!/usr/bin/env bash
# Compile the original toolchain's unmodified atomic.cr with a minimal test
# prelude. Both cmpxchg projections must survive source calls and tuple returns.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}"
CRYSTAL_BIN="${CRYSTAL_BIN:-$(command -v crystal)}"
: "${CRYSTAL_PATH:?Set CRYSTAL_PATH to the original toolchain unmodified stdlib}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/atomic-cmpxchg-result.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

# These declarations provide only the empty-prelude runtime used by the test.
# The Atomic implementation and LLVM enum declarations come from CRYSTAL_PATH.
cat > "$WORK_DIR/common.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class Object
  def unsafe_as(type : T.class) forall T
    x = self
    pointerof(x).as(T*).value
  end
end
struct Pointer(T)
  @[Primitive(:pointer_get)]
  def value : T
  end
end
struct Int
  alias Primitive = Int8 | Int16 | Int32 | Int64 | Int128 | UInt8 | UInt16 | UInt32 | UInt64 | UInt128
end
struct Int32
  @[Primitive(:binary)]
  def ==(other : Int32) : Bool
  end
end
struct Enum
  def ==(other : self)
    value == other.value
  end
end
class ArgumentError
  def initialize(message : String)
  end
end
def raise(error) : NoReturn
  LibC.exit(91)
end
require "atomic"
CR

cat "$WORK_DIR/common.cr" > "$WORK_DIR/int32.cr"
cat >> "$WORK_DIR/int32.cr" <<'CR'
a = Atomic(Int32).new(2)
old = a.swap(3, :relaxed)
hit = a.compare_and_set(3, 4, :acquire_release, :acquire)
miss = a.compare_and_set(3, 9, :relaxed, :relaxed)
LibC.exit(1) unless old == 2
LibC.exit(2) unless hit[0] == 3 && hit[1]
LibC.exit(3) unless miss[0] == 4
LibC.exit(4) if miss[1]
new_value = a.set(17, :release)
LibC.exit(5) unless new_value == 17
LibC.exit(a.get(:acquire) == 17 ? 17 : 6)
CR

cat "$WORK_DIR/common.cr" > "$WORK_DIR/bool.cr"
cat >> "$WORK_DIR/bool.cr" <<'CR'
a = Atomic(Bool).new(false)
old = a.swap(true, :relaxed)
hit = a.compare_and_set(true, false)
miss = a.compare_and_set(true, true, :acquire, :relaxed)
LibC.exit(1) if old
LibC.exit(2) unless hit[0] && hit[1]
LibC.exit(3) if miss[0]
LibC.exit(4) if miss[1]
a.set(true, :release)
LibC.exit(a.get(:acquire) ? 17 : 5)
CR

cat "$WORK_DIR/common.cr" > "$WORK_DIR/mixed_instances.cr"
cat >> "$WORK_DIR/mixed_instances.cr" <<'CR'
integer = Atomic(Int32).new(3)
flag = Atomic(Bool).new(true)
integer_result = integer.compare_and_set(3, 4)
flag_result = flag.compare_and_set(true, false)
LibC.exit(1) unless integer_result[0] == 3 && integer_result[1]
LibC.exit(2) unless flag_result[0] && flag_result[1]
LibC.exit(3) if flag.get
LibC.exit(integer.get == 4 ? 17 : 4)
CR

for name in invalid_load invalid_store invalid_cas_release invalid_cas_stronger; do
  cat "$WORK_DIR/common.cr" > "$WORK_DIR/$name.cr"
  echo 'a = Atomic(Int32).new(3)' >> "$WORK_DIR/$name.cr"
done
echo 'a.get(:release)' >> "$WORK_DIR/invalid_load.cr"
echo 'a.set(4, :acquire)' >> "$WORK_DIR/invalid_store.cr"
echo 'a.compare_and_set(3, 4, :acquire_release, :release)' >> "$WORK_DIR/invalid_cas_release.cr"
echo 'a.compare_and_set(3, 4, :relaxed, :acquire)' >> "$WORK_DIR/invalid_cas_stronger.cr"
for name in invalid_load invalid_store invalid_cas_release invalid_cas_stronger; do
  echo 'LibC.exit(7)' >> "$WORK_DIR/$name.cr"
done

cases=(int32:17 bool:17 mixed_instances:17 invalid_load:91 invalid_store:91 invalid_cas_release:91 invalid_cas_stronger:91)
for compiler in crystal adamas; do
  for entry in "${cases[@]}"; do
    name="${entry%:*}"
    expected="${entry#*:}"
    binary="$WORK_DIR/$name.$compiler"
    if [[ "$compiler" == crystal ]]; then
      command=("$SAFE" "$CRYSTAL_BIN" 120 3072 build "$WORK_DIR/$name.cr" --prelude=empty -o "$binary")
    else
      command=("$SAFE" "$ADAMAS_BIN" 120 3072 "$WORK_DIR/$name.cr" --no-prelude --no-ast-cache --no-llvm-cache -o "$binary")
    fi
    if ! "${command[@]}" > "$binary.build.log" 2>&1; then
      echo "FAIL $name: $compiler build"
      tail -n 18 "$binary.build.log"
      exit 1
    fi
    set +e
    "$SAFE" "$binary" 5 256 > "$binary.run.log" 2>&1
    actual=$?
    set -e
    if [[ "$actual" != "$expected" ]]; then
      echo "FAIL $name: $compiler exit $actual, expected $expected"
      tail -n 12 "$binary.run.log"
      exit 1
    fi
    echo "PASS $compiler $name (exit $actual)"
  done
done

echo "PASS: ${#cases[@]} unmodified Atomic source cases match original Crystal"
