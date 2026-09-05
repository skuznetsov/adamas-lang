require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_grouped_union_type_ref(name : String) : Adamas::HIR::TypeRef
    type_ref_for_name(name)
  end

  def __test_grouped_union_hir_type_ref(type_ref : Adamas::MIR::TypeRef) : Adamas::HIR::TypeRef
    mir_to_hir_type_ref(type_ref)
  end
end

private def grouped_union_converter(source : String? = nil) : Adamas::HIR::AstToHir
  if source
    parser = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new(source),
    )
    result = parser.parse_program
    converter = Adamas::HIR::AstToHir.new(result.arena)
    converter.arena = result.arena
    result.roots.each do |root_id|
      if node = result.arena[root_id].as?(Adamas::Compiler::Frontend::ClassNode)
        converter.register_class(node)
      end
    end
    converter
  else
    Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
  end
end

private def grouped_union_descriptor(
  converter : Adamas::HIR::AstToHir,
  type_ref : Adamas::HIR::TypeRef,
) : Adamas::MIR::UnionDescriptor
  type_descriptor = converter.module.get_type_descriptor(type_ref)
  type_descriptor.should_not be_nil
  type_descriptor.not_nil!.kind.should eq(Adamas::HIR::TypeKind::Union)
  descriptor = converter.union_descriptors.values.find do |candidate|
    candidate.name == type_descriptor.not_nil!.name
  end
  descriptor.should_not be_nil
  descriptor.not_nil!
end

describe "grouped nullable union canonicalization" do
  it "flattens nested enclosing groups and removes duplicate Nil variants" do
    converter = grouped_union_converter
    type_ref = converter.__test_grouped_union_type_ref("((Int64 | Nil))?")
    descriptor = grouped_union_descriptor(converter, type_ref)

    descriptor.name.should eq("Nil | Int64")
    descriptor.variants.map(&.full_name).should eq(["Nil", "Int64"])
    descriptor.variants.none? { |variant| variant.full_name.includes?("|") }.should be_true
  end

  it "canonicalizes explicit duplicate grouped Nil arms" do
    converter = grouped_union_converter
    type_ref = converter.__test_grouped_union_type_ref("((Int64 | Nil)) | Nil")
    descriptor = grouped_union_descriptor(converter, type_ref)

    descriptor.name.should eq("Nil | Int64")
    descriptor.variants.count { |variant| variant.full_name == "Nil" }.should eq(1)
  end

  it "reuses one TypeRef for flat and grouped nullable spellings" do
    converter = grouped_union_converter
    flat = converter.__test_grouped_union_type_ref("Int64?")
    grouped = converter.__test_grouped_union_type_ref("(Int64 | Nil)?")
    nested = converter.__test_grouped_union_type_ref("((Int64 | Nil))?")

    grouped.should eq(flat)
    nested.should eq(flat)
    converter.__test_grouped_union_type_ref("Int64 | Nil").should eq(flat)
  end

  it "keeps unions inside generic arguments as one outer variant" do
    converter = grouped_union_converter(<<-CRYSTAL)
      class Array(T)
      end
    CRYSTAL
    type_ref = converter.__test_grouped_union_type_ref("Array(Int64 | Nil) | Nil")
    descriptor = grouped_union_descriptor(converter, type_ref)

    descriptor.variants.count { |variant| variant.full_name == "Nil" }.should eq(1)
    descriptor.variants.count { |variant| variant.full_name.starts_with?("Array(") }.should eq(1)
    descriptor.variants.any? { |variant| variant.full_name == "Int64" }.should be_false
  end

  it "keeps a union inside a Tuple argument as one outer variant" do
    converter = grouped_union_converter
    type_ref = converter.__test_grouped_union_type_ref("Tuple(Int64 | Nil) | Nil")
    descriptor = grouped_union_descriptor(converter, type_ref)

    descriptor.variants.count { |variant| variant.full_name == "Nil" }.should eq(1)
    tuple_variants = descriptor.variants.select { |variant| variant.full_name.starts_with?("Tuple(") }
    tuple_variants.size.should eq(1)
    tuple_descriptor = converter.module.get_type_descriptor(
      converter.__test_grouped_union_hir_type_ref(tuple_variants.first.type_ref),
    )
    tuple_descriptor.should_not be_nil
    tuple_descriptor.not_nil!.kind.should eq(Adamas::HIR::TypeKind::Tuple)
    tuple_descriptor.not_nil!.type_params.size.should eq(1)
    element_descriptor = converter.module.get_type_descriptor(tuple_descriptor.not_nil!.type_params.first)
    element_descriptor.should_not be_nil
    element_descriptor.not_nil!.kind.should eq(Adamas::HIR::TypeKind::Union)
    element_descriptor.not_nil!.name.should eq("Nil | Int64")
  end

  it "preserves grouping around arrow Proc arms" do
    converter = grouped_union_converter
    type_ref = converter.__test_grouped_union_type_ref("(Int32 -> Int64) | Nil")
    descriptor = grouped_union_descriptor(converter, type_ref)

    descriptor.variants.count { |variant| variant.full_name == "Nil" }.should eq(1)
    proc_variants = descriptor.variants.reject { |variant| variant.full_name == "Nil" }
    proc_variants.size.should eq(1)
    proc_variants.first.full_name.should eq("Proc(Int32, Int64)")
    proc_descriptor = converter.module.get_type_descriptor(
      converter.__test_grouped_union_hir_type_ref(proc_variants.first.type_ref),
    )
    proc_descriptor.should_not be_nil
    proc_descriptor.not_nil!.kind.should eq(Adamas::HIR::TypeKind::Proc)
    proc_descriptor.not_nil!.type_params.should eq([
      Adamas::HIR::TypeRef::INT32,
      Adamas::HIR::TypeRef::INT64,
    ])
  end
end
