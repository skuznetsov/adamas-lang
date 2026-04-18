# Reducer: Int32 negation + puts formatting lowering.
# Originally covered by regression_tests/test_negative_int32_puts.cr (full prelude).
# No stdlib dependency beyond what `puts` needs — minimal reducer.
# Compiled with --no-prelude by regression_tests/run_no_prelude.sh.
# EXPECT: neg=-7
print "neg="
puts -7
