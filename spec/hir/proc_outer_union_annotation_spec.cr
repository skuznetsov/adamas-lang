require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_proc_outer_union_annotation(name : String, signature_scan : Bool = false) : Adamas::HIR::TypeRef
    old_signature_scan = @signature_scan_mode
    begin
      @signature_scan_mode = signature_scan
      annotation_type_ref(name, "ProcUnionContext")
    ensure
      @signature_scan_mode = old_signature_scan
    end
  end

  def __test_proc_outer_union_members(type : Adamas::HIR::TypeRef) : Array(Adamas::HIR::TypeRef)
    descriptor = @module.get_type_descriptor(type).not_nil!
    split_union_type_name(descriptor.name).map { |name| type_ref_for_name(name) }
  end
end

private def proc_outer_union_converter : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    module ProcUnionContext
      alias Callback = Proc(Nil)
      alias Variant = Proc(Nil) | Tuple(Int32, Int32)
      alias ChainedVariant = Variant
    end
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(program.arena)
  converter.register_module(program.arena[program.roots.first].as(Adamas::Compiler::Frontend::ModuleNode))
  converter
end

private def expect_proc_tuple_union(converter : Adamas::HIR::AstToHir, type : Adamas::HIR::TypeRef)
  descriptor = converter.module.get_type_descriptor(type).not_nil!
  descriptor.kind.should eq(Adamas::HIR::TypeKind::Union)
  members = converter.__test_proc_outer_union_members(type)
  members.size.should eq(2)
  arms = members.map { |arm| converter.module.get_type_descriptor(arm).not_nil! }
  proc_arm = arms.find { |arm| arm.kind == Adamas::HIR::TypeKind::Proc }.not_nil!
  proc_arm.type_params.should eq([Adamas::HIR::TypeRef::NIL])
  tuple_arm = arms.find { |arm| arm.kind == Adamas::HIR::TypeKind::Tuple }.not_nil!
  tuple_arm.type_params.should eq([Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::INT32])
end

describe "Proc annotation outer union boundaries" do
  [false, true].each do |signature_scan|
    context = signature_scan ? "signature scan" : "body lowering"

    it "retains separate Proc and Tuple arms during #{context}" do
      converter = proc_outer_union_converter
      type = converter.__test_proc_outer_union_annotation("Proc(Nil) | Tuple(Int32, Int32)", signature_scan)
      expect_proc_tuple_union(converter, type)
    end

    it "retains separate arms through aliases during #{context}" do
      converter = proc_outer_union_converter
      {"Variant", "ChainedVariant", "Callback | Tuple(Int32, Int32)"}.each do |name|
        type = converter.__test_proc_outer_union_annotation(name, signature_scan)
        expect_proc_tuple_union(converter, type)
      end
    end
  end

  it "preserves the same outer union when its Tuple arm comes first" do
    converter = proc_outer_union_converter
    type = converter.__test_proc_outer_union_annotation("Tuple(Int32, Int32) | Proc(Nil)")
    expect_proc_tuple_union(converter, type)
  end

  it "retains a genuine union inside a Proc result" do
    converter = proc_outer_union_converter
    type = converter.__test_proc_outer_union_annotation("Proc(Nil | Int32)")
    descriptor = converter.module.get_type_descriptor(type).not_nil!
    descriptor.kind.should eq(Adamas::HIR::TypeKind::Proc)
    descriptor.type_params.size.should eq(1)
    result = converter.module.get_type_descriptor(descriptor.type_params.first).not_nil!
    result.kind.should eq(Adamas::HIR::TypeKind::Union)
    members = converter.__test_proc_outer_union_members(descriptor.type_params.first)
    members.should contain(Adamas::HIR::TypeRef::NIL)
    members.should contain(Adamas::HIR::TypeRef::INT32)
  end

  it "retains independent union input and result types in a concrete Proc" do
    converter = proc_outer_union_converter
    type = converter.__test_proc_outer_union_annotation("Proc(Int32 | String, Nil | Bool)")
    descriptor = converter.module.get_type_descriptor(type).not_nil!
    descriptor.kind.should eq(Adamas::HIR::TypeKind::Proc)
    descriptor.type_params.size.should eq(2)
    input = converter.module.get_type_descriptor(descriptor.type_params.first).not_nil!
    input.kind.should eq(Adamas::HIR::TypeKind::Union)
    inputs = converter.__test_proc_outer_union_members(descriptor.type_params.first)
    inputs.should contain(Adamas::HIR::TypeRef::INT32)
    inputs.should contain(Adamas::HIR::TypeRef::STRING)
    result = converter.module.get_type_descriptor(descriptor.type_params.last).not_nil!
    result.kind.should eq(Adamas::HIR::TypeKind::Union)
    results = converter.__test_proc_outer_union_members(descriptor.type_params.last)
    results.should contain(Adamas::HIR::TypeRef::NIL)
    results.should contain(Adamas::HIR::TypeRef::BOOL)
  end

  it "preserves an outer Proc union nested inside an Array" do
    converter = proc_outer_union_converter
    type = converter.__test_proc_outer_union_annotation("Array(Proc(Nil) | Tuple(Int32, Int32))")
    descriptor = converter.module.get_type_descriptor(type).not_nil!
    descriptor.kind.should eq(Adamas::HIR::TypeKind::Array)
    descriptor.type_params.size.should eq(1)
    expect_proc_tuple_union(converter, descriptor.type_params.first)
  end
end

private def lower_proc_outer_union_calls(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(program.arena,
    sources_by_arena: {program.arena.object_id.to_u64 => source})
  converter.arena = program.arena
  converter.no_prelude = true
  main = [] of UInt64
  program.roots.each do |root|
    case node = program.arena[root]
    when Adamas::Compiler::Frontend::AliasNode
      converter.register_alias(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
    else
      main << root.index.to_u64
    end
  end
  converter.lower_main(main)
  converter.flush_pending_functions
  converter
end

describe "Proc specialization signature identity" do
  it "keeps the concrete Proc ABI at direct and aliased outer union calls" do
    converter = lower_proc_outer_union_calls(<<-CRYSTAL)
      alias Variant = Proc(Nil) | Tuple(Int32, Int32)
      def direct_probe(value : Proc(Nil) | Tuple(Int32, Int32)) : Bool
        value.is_a?(Proc(Nil))
      end
      def aliased_probe(value : Variant) : Bool
        value.is_a?(Proc(Nil))
      end
      callback = -> { nil }
      tuple = {1, 2}
      direct_probe(callback)
      direct_probe(tuple)
      aliased_probe(callback)
      aliased_probe(tuple)
    CRYSTAL
    {"direct_probe", "aliased_probe"}.each do |base|
      function = converter.module.functions.find { |fn| fn.name == "#{base}$Proc(Nil)" }
      function.should_not be_nil
      function = function.not_nil!
      descriptor = converter.module.get_type_descriptor(function.params.first.type).not_nil!
      descriptor.kind.should eq(Adamas::HIR::TypeKind::Proc)
      descriptor.type_params.should eq([Adamas::HIR::TypeRef::NIL])
      literals = function.blocks.flat_map(&.instructions).select(Adamas::HIR::Literal)
      literals.any? { |literal| literal.value == true }.should be_true
      function.blocks.flat_map(&.instructions).select(Adamas::HIR::UnionIs).should be_empty
    end
  end

  it "distinguishes Proc inputs and results when specializing an untyped callee" do
    converter = lower_proc_outer_union_calls(<<-CRYSTAL)
      def identity_probe(value)
        value
      end
      identity_probe(-> { nil })
      identity_probe(-> { 1 })
      identity_probe(->(value : Int32) { value })
    CRYSTAL
    names = converter.module.functions.select { |fn| fn.name.starts_with?("identity_probe$Proc(") }.map(&.name)
    names.should contain("identity_probe$Proc(Nil)")
    names.should contain("identity_probe$Proc(Int32)")
    names.should contain("identity_probe$Proc(Int32, Int32)")
    names.size.should eq(3)
  end
end
