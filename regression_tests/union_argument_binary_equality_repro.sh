#!/usr/bin/env bash
# Binary ==/!= and explicit operator calls must dispatch each union arm alike.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/union-binary-equality.XXXXXX")"

cleanup() {
  local status=$?
  rm -rf "$WORK_DIR/original.cache" "$WORK_DIR/candidate.cache"
  if [[ "$status" != 0 || "${KEEP_TMP:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

[[ -x "$COMPILER" && -x "$ORIGINAL_CRYSTAL" && -x "$SAFE_RUNNER" ]] || {
  echo "ERROR: candidate, original Crystal, and safe runner must be executable" >&2
  exit 2
}

cat >"$WORK_DIR/probe.cr" <<'CRYSTAL'
lib C
  fun putchar(value : Int32) : Int32
end

class EqualityLeft
  def token : Int32
    42
  end

  def ==(other : self) : Bool
    other.token == 42
  end

  def ==(other : Tuple(Int32)) : Bool
    false
  end

  def !=(other : self) : Bool
    other.token != 42
  end

  def !=(other : Tuple(Int32)) : Bool
    true
  end
end

class ReverseEqualityLeft
  def token : Int32
    42
  end

  def ==(other : Tuple(Int32)) : Bool
    false
  end

  def ==(other : self) : Bool
    other.token == 42
  end

  def !=(other : Tuple(Int32)) : Bool
    true
  end

  def !=(other : self) : Bool
    other.token != 42
  end
end

class VirtualEqualityBase
  def ==(other : Int32) : Bool
    true
  end

  def ==(other : Tuple(Int32)) : Bool
    false
  end

  def !=(other : Int32) : Bool
    false
  end

  def !=(other : Tuple(Int32)) : Bool
    true
  end
end

class VirtualEqualityChild < VirtualEqualityBase
  def ==(other : Tuple(Int32)) : Bool
    true
  end

  def ==(other : Int32) : Bool
    false
  end

  def !=(other : Tuple(Int32)) : Bool
    false
  end

  def !=(other : Int32) : Bool
    true
  end
end

def widen(value : VirtualEqualityBase) : VirtualEqualityBase
  value
end

def virtual_argument(flag : Bool) : Int32 | Tuple(Int32)
  flag ? 1 : {2}
end

class VirtualReturnBase
  def select(value : Int32) : Int32
    65
  end

  def select(value : Tuple(Int32)) : Int32
    66
  end
end

class VirtualReturnChild < VirtualReturnBase
  def select(value : Int32) : Char
    'C'
  end

  def select(value : Tuple(Int32)) : Char
    'D'
  end
end

def widen_return(value : VirtualReturnBase) : VirtualReturnBase
  value
end

def emit_return(value : Int32 | Char)
  if value.is_a?(Char)
    C.putchar(value.as(Char).ord)
  else
    C.putchar(value.as(Int32))
  end
end

def choose(flag : Bool, left : EqualityLeft) : EqualityLeft | Tuple(Int32)
  flag ? left : {7}
end

def reverse_choose(flag : Bool, left : ReverseEqualityLeft) : Tuple(Int32) | ReverseEqualityLeft
  flag ? left : {7}
end

def compare(left : EqualityLeft, right : EqualityLeft | Tuple(Int32)) : Bool
  left == right
end

def different(left : EqualityLeft, right : EqualityLeft | Tuple(Int32)) : Bool
  left != right
end

def emit(value : Bool)
  C.putchar(value ? 84 : 70)
end

left = EqualityLeft.new
same = choose(true, left)
tuple = choose(false, left)
emit(left == same)
emit(left == tuple)
emit(left != same)
emit(left != tuple)
emit(left.==(same))
emit(left.==(tuple))
emit(left.!=(same))
emit(left.!=(tuple))

reverse = ReverseEqualityLeft.new
reverse_same = reverse_choose(true, reverse)
reverse_tuple = reverse_choose(false, reverse)
emit(reverse == reverse_same)
emit(reverse == reverse_tuple)
emit(reverse != reverse_same)
emit(reverse != reverse_tuple)
emit(reverse.==(reverse_same))
emit(reverse.==(reverse_tuple))
emit(reverse.!=(reverse_same))
emit(reverse.!=(reverse_tuple))

emit(compare(left, same))
emit(compare(left, tuple))
emit(different(left, same))
emit(different(left, tuple))
emit(left == left)
emit(left == {7})
emit(left != left)
emit(left != {7})

base = VirtualEqualityBase.new
child = widen(VirtualEqualityChild.new)
integer_argument = virtual_argument(true)
tuple_argument = virtual_argument(false)
emit(base == integer_argument)
emit(base == tuple_argument)
emit(child == integer_argument)
emit(child == tuple_argument)
emit(base != integer_argument)
emit(base != tuple_argument)
emit(child != integer_argument)
emit(child != tuple_argument)
emit(base.==(integer_argument))
emit(base.==(tuple_argument))
emit(child.==(integer_argument))
emit(child.==(tuple_argument))
emit(base.!=(integer_argument))
emit(base.!=(tuple_argument))
emit(child.!=(integer_argument))
emit(child.!=(tuple_argument))

return_base = VirtualReturnBase.new
return_child = widen_return(VirtualReturnChild.new)
emit_return(return_base.select(integer_argument))
emit_return(return_base.select(tuple_argument))
emit_return(return_child.select(integer_argument))
emit_return(return_child.select(tuple_argument))
C.putchar(10)
CRYSTAL

printf 'TFFTTFFTTFFTTFFTTFFTTFFTTFFTFTTFTFFTFTTFABCD\n' >"$WORK_DIR/expected"

run_case() {
  local label="$1" compiler="$2"
  shift 2
  local binary="$WORK_DIR/$label"
  if ! env CRYSTAL_CACHE_DIR="$WORK_DIR/candidate.cache" ADAMAS_LLVM_CACHE=0 \
      ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$label-build.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 "$@" \
      >"$WORK_DIR/$label.build.log" 2>&1; then
    cat "$WORK_DIR/$label.build.log" >&2
    return 1
  fi
  rm -rf "$WORK_DIR/candidate.cache"
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$label-run.resources" \
      "$SAFE_RUNNER" "$binary" 10 512 \
      >"$WORK_DIR/$label.stdout" 2>"$WORK_DIR/$label.run.log"; then
    cat "$WORK_DIR/$label.run.log" >&2
    return 1
  fi
  diff -u "$WORK_DIR/expected" "$WORK_DIR/$label.stdout"
  printf 'PASS[%s]: 44 union/operator/order/forwarding/virtual/return-ABI results match\n' "$label"
}

run_case original "$ORIGINAL_CRYSTAL" build "$WORK_DIR/probe.cr" \
  -o "$WORK_DIR/original" --no-debug --error-trace --link-flags=-fuse-ld=/usr/bin/ld
run_case candidate-no-prelude "$COMPILER" "$WORK_DIR/probe.cr" --no-prelude \
  --no-ast-cache --no-llvm-cache --no-debug -o "$WORK_DIR/candidate-no-prelude"
run_case candidate-full-prelude "$COMPILER" "$WORK_DIR/probe.cr" \
  --no-ast-cache --no-llvm-cache --no-debug -o "$WORK_DIR/candidate-full-prelude"
diff -u "$WORK_DIR/original.stdout" "$WORK_DIR/candidate-no-prelude.stdout"
diff -u "$WORK_DIR/original.stdout" "$WORK_DIR/candidate-full-prelude.stdout"
printf 'PASS: binary union equality dispatch matches explicit operator calls and Crystal\n'
