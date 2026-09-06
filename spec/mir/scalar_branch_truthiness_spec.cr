require "../spec_helper"
require "../../src/compiler/mir/mir"
require "../../src/compiler/mir/hir_to_mir"
require "../../src/compiler/mir/optimizations"
require "../../src/compiler/mir/llvm_backend"

private def scalar_branch_body(type : Adamas::MIR::TypeRef) : String
  mod = Adamas::MIR::Module.new("scalar_truthiness")
  func = mod.create_function("truthy", Adamas::MIR::TypeRef::INT32)
  func.add_param("condition", type)
  yes = func.create_block
  no = func.create_block
  builder = Adamas::MIR::Builder.new(func)
  builder.branch(0_u32, yes, no)
  builder.current_block = yes
  builder.ret(builder.const_int(1_i64, Adamas::MIR::TypeRef::INT32))
  builder.current_block = no
  builder.ret(builder.const_int(0_i64, Adamas::MIR::TypeRef::INT32))
  gen = Adamas::MIR::LLVMIRGenerator.new(mod)
  gen.emit_type_metadata = false
  gen.generate.split("define i32 @truthy", 2)[1].split("}", 2)[0]
end

describe "late MIR scalar branch truthiness" do
  it "always takes the truthy branch for integer and floating values" do
    [Adamas::MIR::TypeRef::INT32, Adamas::MIR::TypeRef::UINT64,
     Adamas::MIR::TypeRef::FLOAT32, Adamas::MIR::TypeRef::FLOAT64].each do |type|
      body = scalar_branch_body(type)
      body.should_not contain("icmp ne")
      body.should_not contain("fcmp")
      body.should contain("br label %bb1")
    end
  end

  it "retains the actual boolean condition" do
    scalar_branch_body(Adamas::MIR::TypeRef::BOOL).should contain("br i1 %condition")
  end

  it "retains nullable pointer checks" do
    scalar_branch_body(Adamas::MIR::TypeRef::POINTER).should contain("icmp ne ptr %condition, null")
  end
end
