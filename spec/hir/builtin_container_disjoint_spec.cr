require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_builtin_container_disjoint(kind : Adamas::HIR::TypeKind, target : Adamas::HIR::TypeRef) : Bool?
    value_type = @module.intern_type(Adamas::HIR::TypeDescriptor.new(kind, "CaseContainer"))
    statically_is_a_type?(value_type, target)
  end
end

describe "Descriptorless builtin targets against known containers" do
  [Adamas::HIR::TypeKind::Array, Adamas::HIR::TypeKind::Hash,
   Adamas::HIR::TypeKind::Tuple, Adamas::HIR::TypeKind::NamedTuple].each do |kind|
    it "proves #{kind} disjoint from concrete builtin targets" do
      converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
      [Adamas::HIR::TypeRef::BOOL, Adamas::HIR::TypeRef::INT8,
       Adamas::HIR::TypeRef::UINT8, Adamas::HIR::TypeRef::INT64,
       Adamas::HIR::TypeRef::FLOAT64, Adamas::HIR::TypeRef::CHAR,
       Adamas::HIR::TypeRef::STRING, Adamas::HIR::TypeRef::NIL,
       Adamas::HIR::TypeRef::SYMBOL, Adamas::HIR::TypeRef::POINTER].each do |target|
        converter.__test_builtin_container_disjoint(kind, target).should eq(false)
      end
    end
  end

  [Adamas::HIR::TypeKind::Class, Adamas::HIR::TypeKind::Struct,
   Adamas::HIR::TypeKind::Module, Adamas::HIR::TypeKind::Generic,
   Adamas::HIR::TypeKind::Union].each do |kind|
    it "keeps #{kind} carriers conservative without hierarchy evidence" do
      converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
      converter.__test_builtin_container_disjoint(kind, Adamas::HIR::TypeRef::UINT8).should be_nil
    end
  end

  it "keeps unknown targets conservative" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_builtin_container_disjoint(Adamas::HIR::TypeKind::Array, Adamas::HIR::TypeRef::VOID).should be_nil
  end
end
