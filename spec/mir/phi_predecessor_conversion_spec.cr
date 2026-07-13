require "../spec_helper"
require "../../src/compiler/mir/mir"
require "../../src/compiler/mir/hir_to_mir"
require "../../src/compiler/mir/optimizations"
require "../../src/compiler/mir/llvm_backend"

describe "LLVM phi predecessor conversions" do
  it "keeps the target width local to each phi" do
    mod = Adamas::MIR::Module.new("phi_predecessor_conversion")
    func = mod.create_function("phi_multi_width", Adamas::MIR::TypeRef::UINT8)
    cond1 = func.add_param("cond1", Adamas::MIR::TypeRef::BOOL)
    cond2 = func.add_param("cond2", Adamas::MIR::TypeRef::BOOL)
    value = func.add_param("value", Adamas::MIR::TypeRef::UINT16)

    left32 = func.create_block
    right32 = func.create_block
    merge32 = func.create_block
    left8 = func.create_block
    right8 = func.create_block
    merge8 = func.create_block

    builder = Adamas::MIR::Builder.new(func)
    builder.branch(cond1, left32, right32)

    builder.current_block = left32
    builder.jump(merge32)
    builder.current_block = right32
    builder.jump(merge32)

    builder.current_block = merge32
    phi32 = builder.phi(Adamas::MIR::TypeRef::INT32)
    phi32.add_incoming(from: left32, value: value)
    phi32.add_incoming(from: right32, value: value)
    builder.branch(cond2, left8, right8)

    builder.current_block = left8
    builder.jump(merge8)
    builder.current_block = right8
    builder.jump(merge8)

    builder.current_block = merge8
    phi8 = builder.phi(Adamas::MIR::TypeRef::UINT8)
    phi8.add_incoming(from: left8, value: value)
    phi8.add_incoming(from: right8, value: value)
    builder.ret(phi8.id)
    func.compute_predecessors

    generator = Adamas::MIR::LLVMIRGenerator.new(mod)
    generator.emit_type_metadata = false
    output = generator.generate
    body = output[/define i8 @phi_multi_width\(.*?\n\}/m].not_nil!

    body.should contain("zext i16 %value to i32")
    body.should contain("trunc i16 %value to i8")
  end
end
