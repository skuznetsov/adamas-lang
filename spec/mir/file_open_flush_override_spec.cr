require "../spec_helper"
require "../../src/compiler/mir/mir"
require "../../src/compiler/mir/hir_to_mir"
require "../../src/compiler/mir/optimizations"
require "../../src/compiler/mir/llvm_backend"

class Adamas::MIR::LLVMIRGenerator
  # Test-only seam for the no-prelude missing-function stub path.
  def __test_emit_dead_code_stub(
    name : String,
    return_type : String,
    arg_count : Int32 = 0,
    arg_types : Array(String) = [] of String,
  ) : String?
    emit_dead_code_stub(name, return_type, arg_count, arg_types)
  end
end

private def file_open_test_module : Adamas::MIR::Module
  mod = Adamas::MIR::Module.new("file_open_flush_override")
  # MIR names use Crystal source spelling; the backend mangle pass turns these
  # into File$Dopen$$String_String_block / IO$CCFileDescriptor$Hflush.
  file_open = mod.create_function("File.open$String_String_block", Adamas::MIR::TypeRef::POINTER)
  file_open.add_param("path", Adamas::MIR::TypeRef::POINTER)
  file_open.add_param("mode", Adamas::MIR::TypeRef::POINTER)
  file_open.add_param("block", Adamas::MIR::TypeRef::POINTER)
  builder = Adamas::MIR::Builder.new(file_open)
  builder.ret(builder.const_nil_typed(Adamas::MIR::TypeRef::POINTER))

  flush = mod.create_function("IO::FileDescriptor#flush", Adamas::MIR::TypeRef::POINTER)
  flush.add_param("self", Adamas::MIR::TypeRef::POINTER)
  flush_builder = Adamas::MIR::Builder.new(flush)
  flush_builder.ret(flush_builder.const_nil_typed(Adamas::MIR::TypeRef::POINTER))
  mod
end

describe "File.open no-prelude flush override" do
  it "uses the defined IO::FileDescriptor flush symbol in dead-code stubs" do
    generator = Adamas::MIR::LLVMIRGenerator.new(Adamas::MIR::Module.new("stub_probe"))
    ir = generator.__test_emit_dead_code_stub(
      "File$Dopen$$String_String_block",
      "ptr",
      3,
      ["ptr", "ptr", "ptr"]
    )
    ir.should_not be_nil
    ir.not_nil!.should_not contain("@File$Hflush")
    ir.not_nil!.should contain("@IO$CCFileDescriptor$Hflush")
  end

  it "keeps the builtin override call target defined in generated LLVM" do
    generator = Adamas::MIR::LLVMIRGenerator.new(file_open_test_module)
    generator.emit_type_metadata = false
    output = generator.generate
    output.should_not contain("call ptr @File$Hflush")
    output.should contain("call ptr @IO$CCFileDescriptor$Hflush")
    output.should contain("define ptr @IO$CCFileDescriptor$Hflush")
  end
end
