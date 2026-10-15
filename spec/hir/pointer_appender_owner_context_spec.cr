require "spec"
require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_pointer_appender_fallback_name(
    exact_target : String,
    fallback_base : String,
    owner : String,
  ) : String
    request = ReceiverRepairFallback.new(
      exact_target,
      fallback_base,
      owner,
      [] of Adamas::HIR::TypeRef,
      false,
      false,
      false,
      "Pointer::Appender#test",
    )
    receiver_repair_fallback_lookup_name(request)
  end
end

describe "Pointer::Appender receiver-repair owner specialization" do
  it "retains the concrete overload suffix when specializing the authenticated owner" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)

    converter.__test_pointer_appender_fallback_name(
      "Pointer::Appender#<<$UInt8",
      "Pointer::Appender#<<",
      "Pointer::Appender(UInt8)",
    ).should eq("Pointer::Appender(UInt8)#<<$UInt8")

    converter.__test_pointer_appender_fallback_name(
      "Pointer::Appender#<<$Int32",
      "Pointer::Appender#<<",
      "Pointer::Appender(Int32)",
    ).should eq("Pointer::Appender(Int32)#<<$Int32")
  end

  it "keeps unrelated ancestor fallbacks and concrete targets unchanged" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)

    converter.__test_pointer_appender_fallback_name(
      "Indexable(T)#fetch$Int32",
      "Indexable(T)#fetch",
      "Pointer::Appender(UInt8)",
    ).should eq("Indexable(T)#fetch")

    converter.__test_pointer_appender_fallback_name(
      "Pointer::Appender(UInt8)#<<$UInt8",
      "Pointer::Appender#<<",
      "Pointer::Appender(UInt8)",
    ).should eq("Pointer::Appender(UInt8)#<<")
  end
end
