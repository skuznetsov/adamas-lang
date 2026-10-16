require "../spec_helper"
require "../../src/compiler/mir/hir_to_mir"
require "../../src/compiler/mir/optimizations"
require "../../src/compiler/mir/llvm_backend"

class Adamas::MIR::LLVMIRGenerator
  def __test_string_byte_pointer_stub(name : String, result : String, count : Int32, args : Array(String)) : String?
    emit_dead_code_stub(name, result, count, args)
  end
end

describe "String byte-pointer backend contract" do
  it "uses the native copy constructor for an ABI-matched missing body" do
    generator = Adamas::MIR::LLVMIRGenerator.new(Adamas::MIR::Module.new("string_copy"))
    body = generator.__test_string_byte_pointer_stub("String$Dnew$$Pointer$LUInt8$R", "ptr", 1, ["ptr"]).not_nil!
    body.should contain("call i64 @strlen(ptr %chars)")
    body.should contain("call ptr @String$Dnew$$Pointer$LUInt8$R_Int32_Int32(")
    body.should_not contain("allocator stub")
  end

  it "requires the exact result, count and argument ABI" do
    generator = Adamas::MIR::LLVMIRGenerator.new(Adamas::MIR::Module.new("string_abi_guard"))
    [{"i64", 1, ["ptr"]}, {"ptr", 2, ["ptr", "i32"]}, {"ptr", 1, ["i64"]}].each do |shape|
      body = generator.__test_string_byte_pointer_stub("String$Dnew$$Pointer$LUInt8$R", shape[0], shape[1], shape[2])
      (body || "").should_not contain("call i64 @strlen(ptr %chars)")
    end
  end

  it "does not attach the String contract to another constructor owner or pointee" do
    generator = Adamas::MIR::LLVMIRGenerator.new(Adamas::MIR::Module.new("string_identity_guard"))
    ["UserBytes$Dnew$$Pointer$LUInt8$R", "String$Dnew$$Pointer$LInt8$R"].each do |name|
      body = generator.__test_string_byte_pointer_stub(name, "ptr", 1, ["ptr"])
      (body || "").should_not contain("call i64 @strlen(ptr %chars)")
    end
  end
end
