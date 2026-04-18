# Reducer: Proc literal allocation + closure capture lowering.
# Relevant to the "broken Proc/closure capture" class of V2 bugs (MEMORY.md):
# closures received null `self` before the 2026-03-21 fix batch. Guards the
# non-vdispatch `.call` lowering (direct Proc invocation — not routed through
# a shared stdlib iterator).
# Covers what regression_tests/test_proc_basic.cr covered, full-prelude-free.
# EXPECT: proc_test_done
adder = ->(a : Int32, b : Int32) { a + b }
puts adder.call(3, 4)

x = 10
multiplier = ->(n : Int32) { n * x }
puts multiplier.call(5)

puts "proc_test_done"
