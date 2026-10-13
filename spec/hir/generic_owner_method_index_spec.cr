require "spec"
require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_filter_method_candidates(
    candidates : Array(String),
    requested_owner : String,
    separator : Char = '#',
  ) : Array(String)
    filter_method_index_candidates_for_owner(candidates, requested_owner, separator)
  end

  def __test_type_parameter_only(arg : String, declared_params : Array(String)) : Bool
    method_index_type_parameter_only?(arg, declared_params)
  end

  def __test_receiver_repair_fallback_lookup_name(owner : String, fallback_base : String) : String
    request = ReceiverRepairFallback.new(
      "#{owner}#[]$Int32_Int32",
      fallback_base,
      owner,
      [] of Adamas::HIR::TypeRef,
      false,
      false,
      false,
      "test",
    )
    receiver_repair_fallback_lookup_name(request)
  end
end

describe "generic method-index owner filtering" do
  it "prefers the exact owner over template and bare fallbacks while rejecting concrete siblings" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    candidates = [
      "Array(Time::Location::ZoneTransition)#fetch$Int32_Nil",
      "Array(Hash(String, UInt32))#fetch$Int32_Nil",
      "Array(T)#fetch$Int32_Nil",
      "Array#fetch$Int32_Nil",
      "Indexable(T)#fetch$Int32_Nil",
    ]

    selected = converter.__test_filter_method_candidates(
      candidates,
      "Array(Hash(String, UInt32))",
    )

    selected.should eq([
      "Array(Hash(String, UInt32))#fetch$Int32_Nil",
    ])
  end

  it "preserves inherited module templates and separator ownership" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    candidates = [
      "Indexable(T)#fetch$Int32_Nil",
      "Indexable#fetch$Int32_Nil",
      "Indexable(T).fetch$Int32_Nil",
    ]

    converter.__test_filter_method_candidates(candidates, "Indexable(String)").should eq([
      "Indexable(T)#fetch$Int32_Nil",
      "Indexable#fetch$Int32_Nil",
    ])
    converter.__test_filter_method_candidates(candidates, "Indexable(String)", '.').should eq([
      "Indexable(T).fetch$Int32_Nil",
    ])
  end

  it "leaves non-generic lookup buckets unchanged" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    candidates = [
      "Array(Time)#fetch$Int32_Nil",
      "Array(Hash(String, UInt32))#fetch$Int32_Nil",
    ]
    converter.__test_filter_method_candidates(candidates, "Array").should eq(candidates)
  end

  it "accepts only the supplied declared type parameters" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)

    converter.__test_type_parameter_only("T", ["T"]).should be_true
    converter.__test_type_parameter_only("X", ["T"]).should be_false
    converter.__test_type_parameter_only("Array(T)", ["T"]).should be_true
    converter.__test_type_parameter_only("Array(String)", ["T"]).should be_false

    deep = "Array(" * 10 + "T" + ")" * 10
    converter.__test_type_parameter_only(deep, ["T"]).should be_true
  end

  it "formats same-family receiver repair fallback keys without changing ancestors" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)

    converter.__test_receiver_repair_fallback_lookup_name(
      "Slice(Pointer(Event))",
      "Slice#[]",
    ).should eq("Slice(Pointer(Event))#[]")
    converter.__test_receiver_repair_fallback_lookup_name(
      "Array(Hash(String, UInt32))",
      "Array#fetch",
    ).should eq("Array(Hash(String, UInt32))#fetch")
    converter.__test_receiver_repair_fallback_lookup_name(
      "Array(Hash(String, UInt32))",
      "Indexable#fetch",
    ).should eq("Indexable#fetch")
  end
end
