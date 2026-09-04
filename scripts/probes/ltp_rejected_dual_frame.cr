# Manual RED probe for retained MIR mutation after a rejected dual-frame attempt.
# Build with the host Crystal compiler; execute only through scripts/run_safe.sh.
# Exit 1 means this witness violates the acceptance contract, not a miscompile.
# Move the witness into spec/compiler/mir/ltp_wba_spec.cr with the contract repair.
require "../../src/compiler/mir/mir"
require "../../src/compiler/mir/optimizations"

int_type = Adamas::MIR::TypeRef::INT32
func = Adamas::MIR::Function.new(Adamas::MIR::FunctionId.new(9001_u32), "ltp_reject_probe", int_type)
entry = func.get_block(func.create_block)
left = Adamas::MIR::Constant.new(1_u32, int_type, 10_i64)
right = Adamas::MIR::Constant.new(2_u32, int_type, 32_i64)
add = Adamas::MIR::BinaryOp.new(3_u32, int_type, Adamas::MIR::BinOp::Add, left.id, right.id)
alloc = Adamas::MIR::Alloc.new(4_u32, int_type, Adamas::MIR::MemoryStrategy::ARC, int_type)

# Stores keep both operands live, preventing DCE from supplying a later descent.
entry.add(left)
entry.add(right)
entry.add(add)
entry.add(alloc)
entry.add(Adamas::MIR::Store.new(5_u32, alloc.id, left.id))
entry.add(Adamas::MIR::Store.new(6_u32, alloc.id, right.id))
entry.terminator = Adamas::MIR::Return.new(add.id)

engine = Adamas::MIR::LTPEngine.new(func)
initial = engine.frame_potential
before = entry.instructions.map(&.class.name)
reported = engine.run(max_iters: 1)
retained = engine.frame_potential
after = entry.instructions.map(&.class.name)
violation = before != after && retained == initial && engine.potential_trace.size == 1

puts "initial=#{initial} reported=#{reported} retained=#{retained}"
puts "trace=#{engine.potential_trace}"
puts "before=#{before}"
puts "after=#{after}"
puts "rejected_mutation_retained=#{violation}"
exit(violation ? 1 : 0)
