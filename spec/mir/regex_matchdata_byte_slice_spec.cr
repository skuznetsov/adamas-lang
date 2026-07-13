require "../spec_helper"
require "../../src/compiler/mir/mir"
require "../../src/compiler/mir/hir_to_mir"
require "../../src/compiler/mir/optimizations"
require "../../src/compiler/mir/llvm_backend"

describe "Regex::MatchData runtime override" do
  it "uses the unconditional string byte-slice helper" do
    mod = Adamas::MIR::Module.new("regex_matchdata_byte_slice")
    function = mod.create_function("Regex::MatchData#[]$Int32", Adamas::MIR::TypeRef::POINTER)
    function.add_param("self", Adamas::MIR::TypeRef::POINTER)
    function.add_param("index", Adamas::MIR::TypeRef::INT32)

    generator = Adamas::MIR::LLVMIRGenerator.new(mod)
    generator.emit_type_metadata = false
    output = generator.generate
    body = output[/define ptr @Regex\$CCMatchData\$H\$IDX\$\$Int32\(.*?\n\}/m].not_nil!

    body.should contain("call ptr @__adamas_string_byte_slice(ptr %str, i32 %start, i32 %len)")
    body.should_not contain("call ptr @String$Hbyte_slice$$Int32_Int32")
  end
end
