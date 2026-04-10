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
# EXPECT: pw2ceil_primitive_ok

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
