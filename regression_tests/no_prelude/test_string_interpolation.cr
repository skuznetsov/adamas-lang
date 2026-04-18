# Reducer: HIR StringInterpolation lowering → MIR → __crystal_v2_string_interpolate.
# See ast_to_hir#lower_string_interpolation, llvm_backend#emit_string_interpolate.
# Does not depend on String::Builder (full-prelude integration path). Covers what
# regression_tests/test_string_interp.cr covered, minus the full-prelude compile tax.
# EXPECT: string_interp_done
name = "world"
age = 42
puts "Hello, #{name}! Age: #{age}"
puts "string_interp_done"
