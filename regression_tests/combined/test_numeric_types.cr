# Combined: Int types, Float types, conversions, arithmetic
# EXPECT: numeric_types_all_ok

# --- Int32 arithmetic ---
a = 10
b = 3
puts a + b
puts a - b
puts a * b
puts a // b
puts a % b

# --- Int64 ---
big = 1_i64 << 40
puts big > 0
puts big.class

# --- UInt types ---
u8 = 255_u8
puts u8
u16 = 65535_u16
puts u16
u32 = 4294967295_u32
puts u32

# --- Float64 ---
f = 3.14159
puts f > 3.0
puts f < 4.0

# --- Float arithmetic ---
puts 1.0 / 3.0 > 0.3
puts 2.5 * 4.0

# --- Mixed numeric ---
int_val = 42
float_val = int_val.to_f
puts float_val

# --- Comparisons ---
puts 1 < 2
puts 2 > 1
puts 1 <= 1
puts 2 >= 2
puts 1 == 1
puts 1 != 2

# --- Bitwise ---
puts 0xFF & 0x0F
puts 0xF0 | 0x0F
puts 0xFF ^ 0x0F
puts 1 << 4
puts 16 >> 2

# --- Absolute value ---
puts -42.abs
puts 42.abs

# --- Min/Max ---
puts Math.min(3, 7)
puts Math.max(3, 7)

# --- Power ---
puts 2 ** 10

# --- Numeric conversions ---
puts 42.to_s
puts 42.to_f
puts 3.14.to_i
puts 255.to_u8

# --- Overflow-safe ---
max_i32 = Int32::MAX
puts max_i32
min_i32 = Int32::MIN
puts min_i32

puts "numeric_types_all_ok"
