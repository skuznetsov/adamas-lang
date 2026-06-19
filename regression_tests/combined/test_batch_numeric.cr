# Combined batch bundle (mechanical concat, byte-equality verified).
# Members: test_float_pow_var math_pw2ceil_primitive float_unsafe_as_bits union_primitive_binary_op named_tuple_literal_index_runtime case_tuple_bool_match
# EXPECT: test_batch_numeric_all_ok

# ===== test_float_pow_var =====

x = 3.0
value = x ** 2
if value == 9.0
  puts "float_pow_var_ok"
else
  puts "float_pow_var_bad: #{value}"
end

# ===== math_pw2ceil_primitive =====
# Regression: Math.pw2ceil + Int#next_power_of_two across primitive types.
#
# Root cause (fixed): preserve_requested_value_owner_specialization? normalized
# method owner names via @type_param_map during primitive template lowering,
# collapsing "Int32" and "Int" both to "Int32". That hid the need to preserve
# the concrete primitive specialization and caused Int32#next_power_of_two to
# be lowered under the abstract "Int#next_power_of_two" name, leaving the
# concrete call site unresolved and routed to the STUB fallback (exit 134).
#
# This test exercises Math.pw2ceil and direct .next_power_of_two on several
# primitive Int types so any future regression in the primitive-template
# specialization path trips the test.
#

puts Math.pw2ceil(1)          # 1
puts Math.pw2ceil(33)         # 64
puts Math.pw2ceil(1024)       # 1024
puts Math.pw2ceil(1025)       # 2048

puts 1_i64.next_power_of_two          # 1
puts 33_i64.next_power_of_two         # 64
puts 70_000_i64.next_power_of_two     # 131072

puts 33_u32.next_power_of_two         # 64
puts 1_000_u32.next_power_of_two      # 1024

puts 7_i8.next_power_of_two           # 8
puts 17_u16.next_power_of_two         # 32

puts "pw2ceil_primitive_ok"

# ===== float_unsafe_as_bits =====
# Regression: Float64#unsafe_as(UInt64) must preserve the IEEE bit pattern.
#
# Before the LLVM backend fix, same-width float->int unsafe_as casts were
# coerced to fptoui/fptosi, so 236.15_f64.unsafe_as(UInt64) produced 236
# instead of 0x406d84cccccccccd. That broke Ryu-based float formatting and made
# benchmark timing lines print bogus 0.000 values.
#
# bits=4642512806033018061
# hex=406d84cccccccccd

value = 236.15_f64
bits = value.unsafe_as(UInt64)

puts "bits=#{bits}"
puts "hex=#{bits.to_s(16)}"

# ===== union_primitive_binary_op =====
# Regression: primitive-union receiver binary ops (lower_binary intercept).
#
# Root cause (fixed): when a binary op `left op right` had a union left type
# whose variants were all numeric primitives (e.g. `Int32 | UInt32`), the old
# lowering path in ast_to_hir.cr#lower_binary bypassed the primitive inline
# path (because `is_integer_type` checks only Int8..Int128) and fell through
# either to the non-integer `<<` method branch or to `emit_binary_call`.
# Both paths built a method name like `Int32 | UInt32#%$Int32` and emitted a
# Call with virtual=false. hir_to_mir couldn't resolve the method, routed to
# extern_call, and crashed at runtime with:
#   STUB CALLED: Int32$_$OR$_UInt32$H$MOD$$Int32
#   STUB CALLED: Int32$_$OR$_UInt32$H$SHL$$Int32
#
# Fix: try_lower_binary_primitive_union dispatches per variant inline via
# UnionIs / UnionUnwrap / BinaryOperation / UnionWrap / Phi, wrapping
# arithmetic results back into the source union so downstream types match
# Crystal semantics.
#
# This test exercises %, //, <<, >>, +, -, *, and comparison on a mixed
# Int32 | UInt32 receiver so any regression in the inline dispatch trips it.
#

d : Int32 | UInt32 = 236_i32
d = 236_u32 if 1 == 1

raise "d % 10" unless (d % 10) == 6          # UInt32 % Int32
raise "d // 10" unless (d // 10) == 23       # UInt32 // Int32
raise "d << 1" unless (d << 1) == 472
raise "d >> 2" unless (d >> 2) == 59
raise "d + 4" unless (d + 4) == 240
raise "d - 6" unless (d - 6) == 230
raise "d * 2" unless (d * 2) == 472

# Comparison returns Bool on both variants.
raise "d > 100" unless d > 100
raise "d == 236" unless d == 236

# Negative signed path (flooring semantics for // and %).
s : Int32 | UInt32 = -7_i32
raise "s % 3" unless (s % 3) == 2            # flooring, not truncating
raise "s // 3" unless (s // 3) == -3

puts "union_prim_binop_ok"

# ===== named_tuple_literal_index_runtime =====
nt = {base: "ok", args: "yy"}
puts nt[:base]
puts nt[:args]

# ===== case_tuple_bool_match =====
left = false
right = false
result = "ELSE"

case {left, right}
when {true, true}
  result = "TT"
when {false, false}
  result = "FF"
else
  result = "ELSE"
end

puts result

puts "test_batch_numeric_all_ok"
