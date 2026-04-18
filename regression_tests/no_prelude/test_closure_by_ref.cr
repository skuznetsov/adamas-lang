# Reducer: by-reference closure capture through an explicit `&block : ->` param.
# MEMORY.md "Mutable outer-var mutation in blocks broken" (2026-04-04):
#   Direct `call_block { x = 42 }` MUST propagate the mutation back to the caller.
#   Only blocks routed through stdlib `Array#each` / `Range#each` (which convert
#   them to Procs) are affected by the live V2 bug. This reducer guards the
#   direct path — a regression here would mean a fresh compiler break.
# Covers what regression_tests/test_closure_ref.cr covered, full-prelude-free.
# EXPECT: 42
def call_block(&block : ->)
  block.call
end

x = 10
call_block do
  x = 42
end
puts x
