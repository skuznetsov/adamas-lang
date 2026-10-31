#!/usr/bin/env bash
# An inherited value body must execute with its concrete receiver owner.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT_DIR/scripts/run_safe.sh"
CANDIDATE="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/binary-value-owner.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  else
    rm -rf -- "$WORK"
  fi
}
trap cleanup EXIT
cat > "$WORK/source.cr" <<'CRYSTAL'
@[Link("c")]
lib BinaryValueOutput
  fun putchar(value : Int32) : Int32
end
abstract struct BinaryValueParent
  def +(other : Int32) : Int32
    payload &+ other
  end
end
struct BinaryValueConcrete < BinaryValueParent
  def payload : Int32
    64
  end
end
module BinaryBoolOperation
  def +(other : Bool) : Int32
    66
  end
end
struct BinaryBoolValue
  include BinaryBoolOperation
end
class BinaryReferenceParent
  def +(other : Bool) : Int32
    65
  end
end
class BinaryReferenceChild < BinaryReferenceParent
  def +(other : Bool) : Int32
    66
  end
end
abstract struct BinarySuperGrandparent
  def +(other : Int32) : Int32
    1
  end
end
abstract struct BinarySuperParent < BinarySuperGrandparent
  abstract def payload : Int32
  def +(other : Int32) : Int32
    BinaryValueOutput.putchar(65)
    payload &+ super
  end
end
struct BinarySuperConcrete < BinarySuperParent
  def payload : Int32
    64
  end
end
def binary_reference_call(value : BinaryReferenceParent) : Int32
  value + true
end
BinaryValueOutput.putchar(BinaryValueConcrete.new + 1)
BinaryValueOutput.putchar(BinaryBoolValue.new + true)
BinaryValueOutput.putchar(BinaryReferenceParent.new + true)
BinaryValueOutput.putchar(BinaryReferenceChild.new + true)
BinaryValueOutput.putchar(binary_reference_call(BinaryReferenceParent.new))
BinaryValueOutput.putchar(binary_reference_call(BinaryReferenceChild.new))
super_value = BinarySuperConcrete.new + 1
BinaryValueOutput.putchar(super_value == 65 ? 66 : 88)
BinaryValueOutput.putchar(10)
CRYSTAL
printf 'ABABABAB\n' > "$WORK/expected.stdout"
for mode in stock lazy eager; do
  if [[ "$mode" == stock ]]; then
    CRYSTAL_CACHE_DIR="$WORK/cache.stock" "$SAFE" "$ORIGINAL" 120 4096 \
      build --prelude=empty --no-debug --link-flags="$LINK_FLAGS" \
      "$WORK/source.cr" -o "$WORK/$mode" > "$WORK/$mode.build.log" 2>&1 || {
      cat "$WORK/$mode.build.log" >&2
      exit 1
    }
  else
    mode_env=(env -u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
    [[ "$mode" == eager ]] && mode_env=(env -u ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO=1)
    "${mode_env[@]}" ADAMAS_LLVM_CACHE=0 "$SAFE" "$CANDIDATE" 120 4096 \
      "$WORK/source.cr" --no-prelude --no-debug --no-ast-cache --no-llvm-cache \
      -o "$WORK/$mode" > "$WORK/$mode.build.log" 2>&1 || {
      cat "$WORK/$mode.build.log" >&2
      exit 1
    }
  fi
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$WORK/$mode" 5 512 \
    > "$WORK/$mode.stdout" 2> "$WORK/$mode.run.log" || {
    cat "$WORK/$mode.run.log" >&2
    exit 1
  }
  diff -u "$WORK/expected.stdout" "$WORK/$mode.stdout"
  printf 'PASS: %s concrete binary owner and reference controls\n' "$mode"
done
