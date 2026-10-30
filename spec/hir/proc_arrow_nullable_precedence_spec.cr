require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_proc_arrow_nullable_type(name : String) : Adamas::HIR::TypeRef
    type_ref_for_name(name)
  end

  def __test_bound_proc_arrow_nullable_type(
    name : String,
    bindings : Hash(String, String),
  ) : Adamas::HIR::TypeRef
    bound_annotation_type_ref(name, nil, bindings).not_nil!
  end

  def __test_proc_arrow_nullable_union_members(type : Adamas::HIR::TypeRef) : Array(Adamas::HIR::TypeRef)
    descriptor = @module.get_type_descriptor(type).not_nil!
    split_union_type_name(descriptor.name).map { |name| type_ref_for_name(name) }
  end
end

private def proc_arrow_nullable_converter : Adamas::HIR::AstToHir
  Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
end

private def expect_proc_nullable_union(
  converter : Adamas::HIR::AstToHir,
  type : Adamas::HIR::TypeRef,
  expected_members : Array(Adamas::HIR::TypeRef),
)
  descriptor = converter.module.get_type_descriptor(type).not_nil!
  descriptor.kind.should eq(Adamas::HIR::TypeKind::Union)

  members = converter.__test_proc_arrow_nullable_union_members(type)
  members.size.should eq(expected_members.size)
  expected_members.each { |member| members.should contain(member) }
end

describe "nullable suffix precedence in Proc arrow type names" do
  it "keeps nullable input and result suffixes inside the Proc" do
    converter = proc_arrow_nullable_converter
    type = converter.__test_proc_arrow_nullable_type("Int32? -> Int32?")

    proc_type = converter.module.get_type_descriptor(type).not_nil!
    proc_type.kind.should eq(Adamas::HIR::TypeKind::Proc)
    proc_type.type_params.size.should eq(2)

    expect_proc_nullable_union(converter, proc_type.type_params[0], [
      Adamas::HIR::TypeRef::INT32,
      Adamas::HIR::TypeRef::NIL,
    ])
    expect_proc_nullable_union(converter, proc_type.type_params[1], [
      Adamas::HIR::TypeRef::INT32,
      Adamas::HIR::TypeRef::NIL,
    ])
  end

  it "keeps a nullable result inside a zero-input Proc" do
    converter = proc_arrow_nullable_converter
    type = converter.__test_proc_arrow_nullable_type("-> Int32?")

    proc_type = converter.module.get_type_descriptor(type).not_nil!
    proc_type.kind.should eq(Adamas::HIR::TypeKind::Proc)
    proc_type.type_params.size.should eq(1)
    expect_proc_nullable_union(converter, proc_type.type_params.first, [
      Adamas::HIR::TypeRef::INT32,
      Adamas::HIR::TypeRef::NIL,
    ])
  end

  it "keeps parentheses around an arrow when nullable applies to the Proc" do
    converter = proc_arrow_nullable_converter
    type = converter.__test_proc_arrow_nullable_type("(-> Int32)?")

    expect_proc_nullable_union(converter, type, [
      Adamas::HIR::TypeRef::NIL,
      converter.__test_proc_arrow_nullable_type("-> Int32"),
    ])
    proc_member = converter.__test_proc_arrow_nullable_union_members(type).find do |member|
      converter.module.get_type_descriptor(member).try(&.kind) == Adamas::HIR::TypeKind::Proc
    end.not_nil!
    proc_descriptor = converter.module.get_type_descriptor(proc_member).not_nil!
    proc_descriptor.type_params.should eq([Adamas::HIR::TypeRef::INT32])
  end

  it "keeps a nested nullable Proc as one nullable outer input" do
    converter = proc_arrow_nullable_converter
    type = converter.__test_proc_arrow_nullable_type("((-> Int32)?) -> Int32?")

    outer_proc = converter.module.get_type_descriptor(type).not_nil!
    outer_proc.kind.should eq(Adamas::HIR::TypeKind::Proc)
    outer_proc.type_params.size.should eq(2)

    nullable_proc_input = outer_proc.type_params.first
    expect_proc_nullable_union(converter, nullable_proc_input, [
      Adamas::HIR::TypeRef::NIL,
      converter.__test_proc_arrow_nullable_type("-> Int32"),
    ])

    nullable_result = outer_proc.type_params.last
    expect_proc_nullable_union(converter, nullable_result, [
      Adamas::HIR::TypeRef::INT32,
      Adamas::HIR::TypeRef::NIL,
    ])
  end

  it "keeps an explicit result union inside the Proc" do
    converter = proc_arrow_nullable_converter
    type = converter.__test_proc_arrow_nullable_type("Int32 -> (String | Nil)")

    proc_type = converter.module.get_type_descriptor(type).not_nil!
    proc_type.kind.should eq(Adamas::HIR::TypeKind::Proc)
    proc_type.type_params.size.should eq(2)
    proc_type.type_params.first.should eq(Adamas::HIR::TypeRef::INT32)
    expect_proc_nullable_union(converter, proc_type.type_params.last, [
      Adamas::HIR::TypeRef::STRING,
      Adamas::HIR::TypeRef::NIL,
    ])
  end

  it "keeps an unparenthesized result union inside the Proc" do
    converter = proc_arrow_nullable_converter
    type = converter.__test_proc_arrow_nullable_type("Int32 -> String | Nil")
    proc_type = converter.module.get_type_descriptor(type).not_nil!
    proc_type.kind.should eq(Adamas::HIR::TypeKind::Proc)
    proc_type.type_params.first.should eq(Adamas::HIR::TypeRef::INT32)
    expect_proc_nullable_union(converter, proc_type.type_params.last, [
      Adamas::HIR::TypeRef::STRING,
      Adamas::HIR::TypeRef::NIL,
    ])
  end

  it "keeps a root-qualified pointer suffix on the Proc output" do
    converter = proc_arrow_nullable_converter
    type = converter.__test_proc_arrow_nullable_type("::Int32 -> ::UInt8*")
    proc_type = converter.module.get_type_descriptor(type).not_nil!
    proc_type.kind.should eq(Adamas::HIR::TypeKind::Proc)
    proc_type.type_params.first.should eq(Adamas::HIR::TypeRef::INT32)
    output = converter.module.get_type_descriptor(proc_type.type_params.last).not_nil!
    output.kind.should eq(Adamas::HIR::TypeKind::Pointer)
    output.type_params.should eq([Adamas::HIR::TypeRef::UINT8])
  end

  it "keeps a metaclass suffix in the Proc source result slot" do
    converter = proc_arrow_nullable_converter
    type = converter.__test_proc_arrow_nullable_type("Int32 -> Int32.class")
    proc_type = converter.module.get_type_descriptor(type).not_nil!
    proc_type.kind.should eq(Adamas::HIR::TypeKind::Proc)
    proc_type.type_params.should eq([Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::INT32])
    proc_type.proc_type_literal_slot?(1).should be_true
  end

  it "normalizes explicit and omitted Void outputs without normalizing unknowns" do
    converter = proc_arrow_nullable_converter
    ["->", "-> Void", "Proc(Void)", "Proc(::Void)"].each do |name|
      ref = converter.__test_proc_arrow_nullable_type(name)
      converter.module.get_type_descriptor(ref).not_nil!.type_params.should eq([Adamas::HIR::TypeRef::NIL])
    end
    unknown = converter.__test_proc_arrow_nullable_type("-> UnresolvedProcResult")
    converter.module.get_type_descriptor(unknown).not_nil!.type_params.last.should_not eq(Adamas::HIR::TypeRef::NIL)
  end

  it "keeps an explicit NoReturn output distinct from discarded output" do
    converter = proc_arrow_nullable_converter
    ref = converter.__test_proc_arrow_nullable_type("Int32 -> NoReturn")
    descriptor = converter.module.get_type_descriptor(ref).not_nil!
    descriptor.kind.should eq(Adamas::HIR::TypeKind::Proc)
    descriptor.type_params.last.should_not eq(Adamas::HIR::TypeRef::NIL)
    descriptor.type_params.last.should_not eq(Adamas::HIR::TypeRef::VOID)
  end

  it "binds nullable Proc arrow formals before applying their suffixes" do
    converter = proc_arrow_nullable_converter
    bindings = {"T" => "Int32", "U" => "Int64"}
    type = converter.__test_bound_proc_arrow_nullable_type("T? -> U?", bindings)

    proc_type = converter.module.get_type_descriptor(type).not_nil!
    proc_type.kind.should eq(Adamas::HIR::TypeKind::Proc)
    proc_type.type_params.size.should eq(2)
    expect_proc_nullable_union(converter, proc_type.type_params[0], [
      Adamas::HIR::TypeRef::INT32,
      Adamas::HIR::TypeRef::NIL,
    ])
    expect_proc_nullable_union(converter, proc_type.type_params[1], [
      Adamas::HIR::TypeRef::INT64,
      Adamas::HIR::TypeRef::NIL,
    ])
  end

  it "binds the inner Proc before making a grouped arrow nilable" do
    converter = proc_arrow_nullable_converter
    bindings = {"T" => "Int32", "U" => "Int64"}
    type = converter.__test_bound_proc_arrow_nullable_type("(T -> U)?", bindings)

    expect_proc_nullable_union(converter, type, [
      Adamas::HIR::TypeRef::NIL,
      converter.__test_proc_arrow_nullable_type("Int32 -> Int64"),
    ])
  end

  it "binds an input while normalizing an explicit Void output" do
    converter = proc_arrow_nullable_converter
    bindings = {"T" => "Int32"}
    type = converter.__test_bound_proc_arrow_nullable_type("T -> Void", bindings)
    descriptor = converter.module.get_type_descriptor(type).not_nil!
    descriptor.kind.should eq(Adamas::HIR::TypeKind::Proc)
    descriptor.type_params.should eq([Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::NIL])
  end
end
