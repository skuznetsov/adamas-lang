#!/usr/bin/env bash
# Primitive integer result types belong to the receiver, not operand promotion.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}"
CRYSTAL_BIN="${CRYSTAL_BIN:-$(command -v crystal)}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/integer-binary-result.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat > "$WORK_DIR/common.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
fun __crystal_raise_overflow : NoReturn
  LibC.exit(88)
end
struct Int32
  @[Primitive(:binary)]
  def &+(other : Int32) : self
  end
end
CR

cases=()
add_numeric_case() {
  local name="$1" left="$2" right="$3" op="$4" lhs="$5" rhs="$6" result="$7"
  cases+=("$name")
  cat "$WORK_DIR/common.cr" > "$WORK_DIR/$name.cr"
  local primitive="$op"
  case "$op" in
    '<<') primitive=unsafe_shl ;;
    '>>') primitive=unsafe_shr ;;
    '//') primitive=unsafe_div ;;
    '%') primitive=unsafe_mod ;;
  esac
  cat >> "$WORK_DIR/$name.cr" <<CR
struct $left
  @[Primitive(:binary)]
  def $primitive(other : $right) : self
  end
CR
  if [[ "$primitive" != "$op" ]]; then
    cat >> "$WORK_DIR/$name.cr" <<CR
  def $op(other : $right) : self
    $primitive(other)
  end
CR
  fi
  cat >> "$WORK_DIR/$name.cr" <<CR
  @[Primitive(:binary)]
  def ==(other : $left) : Bool
  end
end
def selected(value : $left) : Int32
  value == $result ? 17 : 4
end
def selected(value : $right) : Int32
  3
end
def arithmetic
  left = $lhs
  right = $rhs
  left $op right
end
LibC.exit(selected(arithmetic))
CR
}

add_numeric_case wrapping_add UInt32 Int32 '&+' 4_u32 3 7_u32
add_numeric_case wrapping_sub UInt32 Int64 '&-' 9_u32 3_i64 6_u32
add_numeric_case wrapping_mul Int8 UInt64 '&*' 3_i8 4_u64 12_i8
add_numeric_case checked_add Int32 UInt32 '+' 4 3_u32 7
add_numeric_case checked_sub UInt8 Int64 '-' 9_u8 3_i64 6_u8
add_numeric_case checked_mul Int16 UInt64 '*' 3_i16 4_u64 12_i16
add_numeric_case bitwise_and UInt32 Int64 '&' 7_u32 3_i64 3_u32
add_numeric_case bitwise_or Int8 UInt64 '|' 4_i8 3_u64 7_i8
add_numeric_case bitwise_xor UInt16 Int32 '^' 7_u16 3 4_u16
add_numeric_case shift_left UInt8 Int64 '<<' 3_u8 2_i64 12_u8
add_numeric_case shift_right Int16 UInt64 '>>' 12_i16 2_u64 3_i16
# Positive operands isolate the result contract from floor/sign edge cases.
add_numeric_case floor_div UInt8 Int64 '//' 12_u8 4_i64 3_u8
add_numeric_case modulo Int8 UInt64 '%' 13_i8 5_u64 3_i8

# Literal receivers still own the result. Literal representability does not
# authorize selecting the unsigned type of the right operand.
for variant in literal_left literal_right typeof_result; do
  cases+=("$variant")
  cat "$WORK_DIR/common.cr" > "$WORK_DIR/$variant.cr"
  cat >> "$WORK_DIR/$variant.cr" <<'CR'
struct Int32
  @[Primitive(:binary)]
  def +(other : UInt32) : self
  end
end
struct UInt32
  @[Primitive(:binary)]
  def &+(other : Int32) : self
  end
end
def selected(value : Int32) : Int32
  17
end
def selected(value : UInt32) : Int32
  3
end
def type_selected(value : UInt32.class) : Int32
  17
end
def type_selected(value : Int32.class) : Int32
  3
end
CR
done
echo 'LibC.exit(selected(1 + 2_u32))' >> "$WORK_DIR/literal_left.cr"
# This case needs only type selection, with the UInt32 overload admitted first.
cat >> "$WORK_DIR/literal_right.cr" <<'CR'
def unsigned_selected(value : UInt32) : Int32
  17
end
def unsigned_selected(value : Int32) : Int32
  3
end
LibC.exit(unsigned_selected(2_u32 &+ 1))
CR
echo 'LibC.exit(type_selected(typeof(2_u32 &+ 1)))' >> "$WORK_DIR/typeof_result.cr"

# The original prelude failure: one wrongly inferred arithmetic argument
# prevents the selected Def from converting both ordering symbols to the enum.
cases+=(generic_enum_arguments)
cat "$WORK_DIR/common.cr" > "$WORK_DIR/generic_enum_arguments.cr"
cat >> "$WORK_DIR/generic_enum_arguments.cr" <<'CR'
struct Int32
  @[Primitive(:binary)]
  def ==(other : Int32) : Bool
  end
end
struct UInt32
  @[Primitive(:binary)]
  def &+(other : Int32) : self
  end
end
struct Enum
  def ==(other : self)
    value == other.value
  end
end
struct EnumCell(T)
  enum Ordering
    Acquire
    Release
  end
  def initialize(@value : T)
  end
  def compare_and_set(cmp : T, new_value : T, success : Ordering, failure : Ordering) : Int32
    success.release? && failure.acquire? ? 17 : 3
  end
end
LibC.exit(EnumCell(UInt32).new(1_u32).compare_and_set(1_u32, 1_u32 &+ 1, :release, :acquire))
CR

cases+=(single_evaluation)
cat "$WORK_DIR/common.cr" > "$WORK_DIR/single_evaluation.cr"
cat >> "$WORK_DIR/single_evaluation.cr" <<'CR'
struct UInt32
  @[Primitive(:binary)]
  def &+(other : Int32) : self
  end
end
struct Int32
  @[Primitive(:binary)]
  def ==(other : Int32) : Bool
  end
end
class Operands
  def initialize
    @count = 0
  end
  def left : UInt32
    @count &+= 1
    2_u32
  end
  def right : Int32
    @count &+= 10
    1
  end
  def count : Int32
    @count
  end
end
def consume(value : UInt32) : Int32
  17
end
operands = Operands.new
result = consume(operands.left &+ operands.right)
LibC.exit(operands.count == 11 ? result : 4)
CR

failures=0
for name in "${cases[@]}"; do
  for compiler in crystal adamas; do
    binary="$WORK_DIR/$name.$compiler"
    if [[ "$compiler" == crystal ]]; then
      command_args=("$CRYSTAL_BIN" 120 2048 build "$WORK_DIR/$name.cr" --prelude=empty -o "$binary")
    else
      command_args=("$ADAMAS_BIN" 120 2048 "$WORK_DIR/$name.cr" --no-prelude --no-ast-cache --no-llvm-cache -o "$binary")
    fi
    if ! "$SAFE" "${command_args[@]}" > "$binary.build.log" 2>&1; then
      echo "FAIL $name: $compiler build"
      tail -n 12 "$binary.build.log"
      failures=$((failures + 1))
      continue
    fi
    set +e
    "$SAFE" "$binary" 5 256 > "$binary.run.log" 2>&1
    actual=$?
    set -e
    if [[ "$actual" != 17 ]]; then
      echo "FAIL $name: $compiler exit $actual, expected 17"
      tail -n 12 "$binary.run.log"
      failures=$((failures + 1))
    fi
  done
  echo "CHECK $name (expected exit 17)"
done

# Returning Int32 from an expression cannot admit its whole signed domain
# into UInt32. In particular, treating a literal operand as unsigned is not
# authority to retype the result of the containing expression.
cat "$WORK_DIR/common.cr" > "$WORK_DIR/reject_signed_expression.cr"
cat >> "$WORK_DIR/reject_signed_expression.cr" <<'CR'
struct Int32
  @[Primitive(:binary)]
  def +(other : UInt32) : self
  end
end
def unsigned_only(value : UInt32) : Int32
  17
end
LibC.exit(unsigned_only(-2 + 1_u32))
CR
for compiler in crystal adamas; do
  binary="$WORK_DIR/rejected.$compiler"
  if [[ "$compiler" == crystal ]]; then
    command_args=("$CRYSTAL_BIN" 120 2048 build "$WORK_DIR/reject_signed_expression.cr" --prelude=empty -o "$binary")
  else
    command_args=("$ADAMAS_BIN" 120 2048 "$WORK_DIR/reject_signed_expression.cr" --no-prelude --no-ast-cache --no-llvm-cache -o "$binary")
  fi
  set +e
  "$SAFE" "${command_args[@]}" > "$binary.build.log" 2>&1
  actual=$?
  set -e
  if [[ "$actual" != 1 || -e "$binary" ]] ||
       ! rg -q 'unsigned_only' "$binary.build.log" ||
       ! rg -q 'Int32' "$binary.build.log" ||
       ! rg -q 'UInt32' "$binary.build.log"; then
    echo "FAIL reject_signed_expression: $compiler must reject Int32 for UInt32 without an executable (exit $actual)"
    tail -n 12 "$binary.build.log"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  echo "FAIL: $failures integer binary result checks"
  exit 1
fi
echo "PASS: ${#cases[@]} integer result cases and 1 type rejection match original Crystal"
