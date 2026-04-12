# Regression: sprintf("%.Nf", Float64) with explicit precision.
#
# Exercises three independent HIR lowering fixes:
#   1. `Char - Char` → Int32 (a6e8d465): lower_binary_primitive inferred Char
#      instead of Int32, so consume_number read the union type-id as precision.
#   2. `===` as comparison op (b9551c85): is_comparison_op? didn't include ===,
#      so BinaryOperation(Eq) for === was typed as the left operand instead of
#      Bool, breaking downstream `if cond` in Ryu's rounding block.
#   3. Case/when branch local mutations (945b900f): lower_case captured branch
#      locals after pop_scope (which restored the pre-push snapshot), silently
#      dropping mutations like `num *= 10; num += digit` inside while loops.
#      Cases 8-10 exercise multi-digit precision that requires this fix.
#
# EXPECT: sprintf_float_precision_ok

raise "case1 got #{sprintf("%.3f", 236.15_f64).inspect}" unless sprintf("%.3f", 236.15_f64) == "236.150"
raise "case2 got #{sprintf("%.1f", 230119292.0_f64).inspect}" unless sprintf("%.1f", 230119292.0_f64) == "230119292.0"
raise "case3 got #{sprintf("%.3f", 1.2345_f64).inspect}" unless sprintf("%.3f", 1.2345_f64) == "1.234"
raise "case4 got #{sprintf("%.0f", 2.5_f64).inspect}" unless sprintf("%.0f", 2.5_f64) == "2"

# Additional precision variants
raise "case5" unless sprintf("%.2f", 1.005_f64) == "1.00"
raise "case6" unless sprintf("%.5f", 0.1_f64) == "0.10000"
raise "case7" unless sprintf("%.0f", 3.5_f64) == "4"

# Multi-digit precision: consume_number parses digits via `case/when`
# inside a `while` loop. This used to silently drop mutations across loop
# iterations because lower_case captured per-branch locals AFTER pop_scope
# (which restored the pre-push snapshot). Fixed by saving the branch
# locals before pop_scope and filtering by AST-assigned variables.
raise "case8" unless sprintf("%.10f", 1.0_f64) == "1.0000000000"
raise "case9" unless sprintf("%.15f", 0.5_f64) == "0.500000000000000"
raise "case10" unless sprintf("%.10f", 3.14159265358979_f64) == "3.1415926536"

# Direct exercise of === operator (regression for is_comparison_op? fix)
c = 50_u8
cond = c === '-'
raise "=== should be false for '2' === '-'" if cond
cond2 = c === '2'
raise "=== should be true for '2' === '2'" unless cond2

puts "sprintf_float_precision_ok"
