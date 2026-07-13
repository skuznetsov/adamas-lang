require "../spec_helper"
require "../../src/compiler/mir/mir"
require "../../src/compiler/mir/llvm_backend"

class Adamas::MIR::LLVMIRGenerator
  def __test_module_function_by_mangled_name(name : String) : Adamas::MIR::Function?
    module_function_by_mangled_name(name)
  end
end

describe "LLVM module function lookup" do
  it "finds both indexed and late-added functions without Array(Function)#find" do
    mir_module = Adamas::MIR::Module.new("lookup")
    indexed = mir_module.create_function("Widget#indexed", Adamas::MIR::TypeRef::VOID)
    generator = Adamas::MIR::LLVMIRGenerator.new(mir_module)

    generator.__test_module_function_by_mangled_name("Widget$Hindexed").should eq(indexed)

    late = mir_module.create_function("Widget#late", Adamas::MIR::TypeRef::VOID)
    generator.__test_module_function_by_mangled_name("Widget$Hlate").should eq(late)
    generator.__test_module_function_by_mangled_name("Widget$Hmissing").should be_nil
  end
end
