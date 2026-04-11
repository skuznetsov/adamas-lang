# Regression: `case value; when .op(arg)` shortcuts must compare the case
# subject directly, without turning the whole `value.op(arg)` condition into a
# Bool and then comparing `subject == Bool`.
#
# The numeric part mirrors Float::Printer::RyuPrintf#decimal_length9. The string
# part guards against lowering all shortcut operators to raw BinaryOperation:
# String equality must keep normal method/content semantics.
# EXPECT: case_when_operator_shortcut_ok

def length9(v : UInt32) : UInt32
  case v
  when .>=(100000000) then 9_u32
  when .>=(10000000)  then 8_u32
  when .>=(1000000)   then 7_u32
  when .>=(100000)    then 6_u32
  when .>=(10000)     then 5_u32
  when .>=(1000)      then 4_u32
  when .>=(100)       then 3_u32
  when .>=(10)        then 2_u32
  else                     1_u32
  end
end

raise "bad length9(5)" unless length9(5_u32) == 1_u32
raise "bad length9(42)" unless length9(42_u32) == 2_u32
raise "bad length9(236)" unless length9(236_u32) == 3_u32
raise "bad length9(1234)" unless length9(1234_u32) == 4_u32
raise "bad length9(999999)" unless length9(999999_u32) == 6_u32
raise "bad length9(100000000)" unless length9(100000000_u32) == 9_u32

dynamic_string = String.new("abc".to_slice)
matched = case dynamic_string
          when .==("abc") then true
          else                 false
          end
raise "bad string shortcut equality" unless matched

not_equal = case dynamic_string
            when .!=("zzz") then true
            else                 false
            end
raise "bad string shortcut inequality" unless not_equal

puts "case_when_operator_shortcut_ok"
