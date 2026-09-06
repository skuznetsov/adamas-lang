require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_annotation_in_type_map(name : String, bindings : Hash(String, String)) : TypeRef
    with_type_param_map(bindings) do
      annotation_type_ref(name, "AnnotationOwner")
    end
  end
end

describe "annotation type cache under generic substitutions" do
  it "separates the same lexical signature across concrete includers" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_annotation_in_type_map("T", {"T" => "Int32"}).should eq(Adamas::HIR::TypeRef::INT32)
    converter.__test_annotation_in_type_map("T", {"T" => "String"}).should eq(Adamas::HIR::TypeRef::STRING)
    converter.__test_annotation_in_type_map("T", {"T" => "Int32"}).should eq(Adamas::HIR::TypeRef::INT32)
  end

  it "does not depend on discovery order" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_annotation_in_type_map("T", {"T" => "String"}).should eq(Adamas::HIR::TypeRef::STRING)
    converter.__test_annotation_in_type_map("T", {"T" => "Int32"}).should eq(Adamas::HIR::TypeRef::INT32)
  end

  it "separates substitutions nested in a generic annotation" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    first = converter.__test_annotation_in_type_map("Array(T)", {"T" => "Int32"})
    second = converter.__test_annotation_in_type_map("Array(T)", {"T" => "String"})
    first.should_not eq(second)
    converter.__test_annotation_in_type_map("Array(T)", {"T" => "Int32"}).should eq(first)
  end
end
