require "../spec_helper"
require "../../src/compiler/mir/mir"
require "../../src/compiler/mir/hir_to_mir"
require "../../src/compiler/mir/optimizations"
require "../../src/compiler/mir/llvm_backend"

describe "source spawn body identity" do
  it "does not substitute a Fiber allocator for a source-defined block method" do
    mod = Adamas::MIR::Module.new("source_spawn")
    function = mod.create_function("spawn$$String_Bool_block", Adamas::MIR::TypeRef::INT32)
    function.add_param("name", Adamas::MIR::TypeRef::POINTER)
    function.add_param("same_thread", Adamas::MIR::TypeRef::BOOL)
    function.add_param("block", Adamas::MIR::TypeRef::POINTER)
    builder = Adamas::MIR::Builder.new(function)
    result = builder.const_int(37_i64, Adamas::MIR::TypeRef::INT32)
    builder.ret(result)

    generator = Adamas::MIR::LLVMIRGenerator.new(mod)
    generator.emit_type_metadata = false
    output = generator.generate
    header = output.lines.find { |line| line.starts_with?("define ") && line.includes?("@spawn") }
    header.should eq("define i32 @spawn$$$$String_Bool_block(ptr %name, i1 %same_thread, ptr %block) {")
    output.should contain("add i32 0, 37")
    output.should_not contain("spawn override")
    output.should_not contain("@__adamas_fiber_entry")
    output.should_not contain("@Fiber__classvar__fibers")
  end
end
