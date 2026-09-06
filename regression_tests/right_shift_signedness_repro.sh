#!/usr/bin/env bash
# Right shift follows the value's signedness, regardless of the count type.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compiler="${1:?usage: $0 COMPILER}"
work="$(mktemp -d "${TMPDIR:-/tmp}/right-shift-signedness.XXXXXX")"
trap 'rm -rf "$work"' EXIT
cat > "$work/shift.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def unsigned_8(value : UInt8, count : Int32) : UInt8
  value >> count
end
def signed_8(value : Int8, count : UInt32) : Int8
  value >> count
end
LibC.exit(11) unless unsigned_8(128_u8, 7) == 1_u8
LibC.exit(21) unless unsigned_8(128_u8, 0) == 128_u8
LibC.exit(31) unless unsigned_8(6_u8, 1) == 3_u8
LibC.exit(41) unless signed_8(-4_i8, 1_u32) == -2_i8
def unsigned_16(value : UInt16, count : Int32) : UInt16
  value >> count
end
def signed_16(value : Int16, count : UInt32) : Int16
  value >> count
end
LibC.exit(12) unless unsigned_16(32768_u16, 15) == 1_u16
LibC.exit(22) unless unsigned_16(32768_u16, 0) == 32768_u16
LibC.exit(32) unless unsigned_16(6_u16, 1) == 3_u16
LibC.exit(42) unless signed_16(-4_i16, 1_u32) == -2_i16
def unsigned_32(value : UInt32, count : Int32) : UInt32
  value >> count
end
def signed_32(value : Int32, count : UInt32) : Int32
  value >> count
end
LibC.exit(13) unless unsigned_32(2147483648_u32, 31) == 1_u32
LibC.exit(23) unless unsigned_32(2147483648_u32, 0) == 2147483648_u32
LibC.exit(33) unless unsigned_32(6_u32, 1) == 3_u32
LibC.exit(43) unless signed_32(-4_i32, 1_u32) == -2_i32
def unsigned_64(value : UInt64, count : Int32) : UInt64
  value >> count
end
def signed_64(value : Int64, count : UInt32) : Int64
  value >> count
end
LibC.exit(14) unless unsigned_64(9223372036854775808_u64, 63) == 1_u64
LibC.exit(24) unless unsigned_64(9223372036854775808_u64, 0) == 9223372036854775808_u64
LibC.exit(34) unless unsigned_64(6_u64, 1) == 3_u64
LibC.exit(44) unless signed_64(-4_i64, 1_u32) == -2_i64
# Construct the high bit at runtime: large UInt128 literals have a separate
# existing truncation bug, outside this shift contract.
def high128(value : UInt128, count : Int32) : UInt128
  value << count
end
def unsigned_128(value : UInt128, count : Int32) : UInt128
  value >> count
end
def signed_128(value : Int128, count : UInt32) : Int128
  value >> count
end
LibC.exit(15) unless unsigned_128(high128(1_u128, 127), 127) == 1_u128
LibC.exit(25) unless unsigned_128(high128(1_u128, 127), 0) == high128(1_u128, 127)
LibC.exit(35) unless unsigned_128(6_u128, 1) == 3_u128
LibC.exit(45) unless signed_128(-4_i128, 1_u32) == -2_i128
def rotate(value : UInt64, count : Int32) : UInt64
  (value << count) | (value >> (64 - count))
end
LibC.exit(51) unless rotate(0x8000000000000001_u64, 7) == 192_u64
LibC.exit(52) unless rotate(0x4000000000000001_u64, 7) == 160_u64
value = 0x8000000000000001_u64
8.times { value = rotate(value, 8) }
LibC.exit(53) unless value == 0x8000000000000001_u64
LibC.exit(0)
CR
if ! "$root/scripts/run_safe.sh" "$compiler" 90 8192 "$work/shift.cr" --no-prelude -o "$work/shift" > "$work/shift.log" 2>&1; then
  cat "$work/shift.log"
  exit 1
fi
if ! "$root/scripts/run_safe.sh" "$work/shift" 5 512 >> "$work/shift.log" 2>&1; then
  cat "$work/shift.log"
  exit 1
fi
echo 'PASS[right-shift-signedness]'
