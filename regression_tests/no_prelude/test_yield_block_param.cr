# Reducer: `def foo(x, &) yield x end` lowering + block return value propagation.
# Related to the 2026-03-17 "flat_map crash" three-layer root cause (MEMORY.md):
#   1. contains_yield_deep? must scan CaseNode value/when for block-to-proc,
#   2. infer_block_param_id must reject non-Proc params as yield targets,
#   3. emit_indirect_call must unwrap union payload before invoking block proc.
# This reducer covers the direct `yield` path without routing through a shared
# stdlib iterator, so it is a pure compiler-feature probe.
# Covers what regression_tests/test_yield.cr covered, full-prelude-free.
# EXPECT: yield_done
def with_value(x : Int32, &)
  yield x
end

result = with_value(42) do |v|
  v * 2
end
puts result
puts "yield_done"
