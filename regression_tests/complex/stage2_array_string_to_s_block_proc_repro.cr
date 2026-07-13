# Bootstrap supply regression: Array(String)#to_s contains two nested blocks
# (`exec_recursive` and `join &.inspect(io)`). A self-hosted compiler must keep
# every referenced `__crystal_block_proc_N` body through HIR finalization and
# RTA; retaining only the FuncPointer leaves an undefined symbol at link time.

items = ["adamas"]
io = String::Builder.new
items.to_s(io)
puts io.to_s
