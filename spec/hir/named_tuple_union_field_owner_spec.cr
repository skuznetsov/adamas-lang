require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_named_tuple_union_owner(name : String) : String
    normalize_method_owner_name(name)
  end

  def __test_named_tuple_union_descriptor(name : String) : Adamas::HIR::TypeDescriptor
    @module.get_type_descriptor(type_ref_for_name(name)).not_nil!
  end
end

describe "NamedTuple owners with union field types" do
  it "keeps a numeric union inside its named field" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_named_tuple_union_owner("NamedTuple(name: String, value: UInt16 | Int32)")
      .should eq("NamedTuple(name: String, value: Int32 | UInt16)")
  end

  it "keeps named tuple union arms inside the labels field" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_named_tuple_union_owner(
      "NamedTuple(value: UInt16 | Int32, labels: NamedTuple(vhost: String) | Hash(String, String))"
    ).should eq(
      "NamedTuple(value: Int32 | UInt16, labels: Hash(String, String) | NamedTuple(vhost: String))"
    )
  end

  it "retains the field order and value descriptor at type materialization" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    descriptor = converter.__test_named_tuple_union_descriptor("NamedTuple(name: String, value: UInt16 | Int32)")
    descriptor.kind.should eq(Adamas::HIR::TypeKind::NamedTuple)
    descriptor.name.should eq("NamedTuple(name: String, value: Int32 | UInt16)")
    descriptor.type_params.size.should eq(2)
    value = converter.module.get_type_descriptor(descriptor.type_params[1]).not_nil!
    value.kind.should eq(Adamas::HIR::TypeKind::Union)
    value.name.should eq("Int32 | UInt16")
  end

  it "still canonicalizes ordinary generic union arguments" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_named_tuple_union_owner("Hash(String, Int32 | UInt16)")
      .should eq("Hash(String, Int32 | UInt16)")
  end
end


describe "NamedTuple union owner normalization" do
  it "normalizes each complete union arm before parsing generic arguments" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_named_tuple_union_owner(
      "NamedTuple(value: UInt16 | Int32) | NamedTuple(value: UInt16 | Int32, labels: Hash(String, String) | NamedTuple(vhost: String))"
    ).should eq(
      "NamedTuple(value: Int32 | UInt16) | NamedTuple(value: Int32 | UInt16, labels: Hash(String, String) | NamedTuple(vhost: String))"
    )
  end

  it "keeps ordinary union owners separate from the last generic member" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_named_tuple_union_owner("String | Hash(String, UInt16 | Int32)")
      .should eq("Hash(String, Int32 | UInt16) | String")
  end
end
