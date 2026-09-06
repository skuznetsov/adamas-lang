require "spec"
require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_tuple_union_includes_primitive_safe?(
    tuple_type : Adamas::HIR::TypeRef,
    needle_type : Adamas::HIR::TypeRef,
  ) : Bool
    tuple_union_includes_primitive_safe?(tuple_type, needle_type)
  end

  def __test_tuple_union_type(name : String) : Adamas::HIR::TypeRef
    type_ref_for_name(name)
  end
end

describe "Tuple union includes? admission" do
  it "admits homogeneous primitive tuple variants" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    tuple_union = converter.__test_tuple_union_type("Tuple(Char) | Tuple(Char, Char)")

    converter.__test_tuple_union_includes_primitive_safe?(
      tuple_union,
      Adamas::HIR::TypeRef::CHAR,
    ).should be_true
  end

  it "rejects mixed primitive element shapes" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    tuple_union = converter.__test_tuple_union_type("Tuple(Char, Int32) | Tuple(Char, Char)")

    converter.__test_tuple_union_includes_primitive_safe?(
      tuple_union,
      Adamas::HIR::TypeRef::CHAR,
    ).should be_false
  end

  it "rejects reference element equality" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    tuple_union = converter.__test_tuple_union_type("Tuple(String) | Tuple(String, String)")

    converter.__test_tuple_union_includes_primitive_safe?(
      tuple_union,
      Adamas::HIR::TypeRef::STRING,
    ).should be_false
  end
end
