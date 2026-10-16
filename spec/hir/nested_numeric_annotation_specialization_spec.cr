require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_nested_numeric_annotation_specialization?(annotation_name : String, actual : String) : Bool
    should_use_exact_call_type_for_annotation?(annotation_name, type_ref_for_name(actual))
  end
end

describe "nested numeric annotation specialization" do
  it "preserves unsigned range endpoints under an abstract Int restriction" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_nested_numeric_annotation_specialization?(
      "Range(Int, Int)", "Range(UInt64, UInt64)",
    ).should be_true
  end

  it "preserves a concrete Number argument" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_nested_numeric_annotation_specialization?(
      "NumericBox(Number)", "NumericBox(UInt64)",
    ).should be_true
  end

  it "preserves a concrete Float argument" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_nested_numeric_annotation_specialization?(
      "NumericBox(Float)", "NumericBox(Float64)",
    ).should be_true
  end

  it "descends through more than one generic argument level" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_nested_numeric_annotation_specialization?(
      "NumericBox(Tuple(Int, Float))", "NumericBox(Tuple(UInt64, Float64))",
    ).should be_true
  end

  it "retains union restrictions within a generic argument" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_nested_numeric_annotation_specialization?(
      "NumericBox(Int | Nil)", "NumericBox(UInt64)",
    ).should be_true
  end

  it "does not request specialization for unrelated concrete arguments" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_nested_numeric_annotation_specialization?(
      "NumericBox(Int32)", "NumericBox(UInt64)",
    ).should be_false
    converter.__test_nested_numeric_annotation_specialization?(
      "NumericBox(Int)", "NumericBox(String)",
    ).should be_false
  end

  it "requires the same generic constructor and argument count" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_nested_numeric_annotation_specialization?(
      "NumericBox(Int)", "OtherBox(UInt64)",
    ).should be_false
    converter.__test_nested_numeric_annotation_specialization?(
      "NumericBox(Int, Int)", "NumericBox(UInt64)",
    ).should be_false
  end

  it "checks every argument before refining a mixed restriction" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_nested_numeric_annotation_specialization?(
      "Range(Int, Int32)", "Range(UInt64, UInt64)",
    ).should be_false
    converter.__test_nested_numeric_annotation_specialization?(
      "Range(Int, Int32)", "Range(UInt64, Int32)",
    ).should be_true
  end

  it "keeps signed and unsigned restrictions distinct" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_nested_numeric_annotation_specialization?(
      "NumericBox(Int::Signed)", "NumericBox(UInt64)",
    ).should be_false
    converter.__test_nested_numeric_annotation_specialization?(
      "NumericBox(Int::Unsigned)", "NumericBox(Int32)",
    ).should be_false
    converter.__test_nested_numeric_annotation_specialization?(
      "NumericBox(Int::Signed)", "NumericBox(Int64)",
    ).should be_true
    converter.__test_nested_numeric_annotation_specialization?(
      "NumericBox(Int::Unsigned)", "NumericBox(UInt64)",
    ).should be_true
  end

  it "retains scalar numeric specialization" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_nested_numeric_annotation_specialization?("Int", "UInt64").should be_true
    converter.__test_nested_numeric_annotation_specialization?("Float", "Float64").should be_true
    converter.__test_nested_numeric_annotation_specialization?("Int32", "UInt64").should be_false
  end
end
