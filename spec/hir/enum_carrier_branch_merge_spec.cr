require "spec"
require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_enum_merge_source(code : String) : Adamas::HIR::AstToHir
  result = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(code)
  ).parse_program
  converter = Adamas::HIR::AstToHir.new(result.arena)
  converter.arena = result.arena
  enums = result.roots.compact_map { |id| result.arena[id].as?(Adamas::Compiler::Frontend::EnumNode) }
  defs = result.roots.compact_map { |id| result.arena[id].as?(Adamas::Compiler::Frontend::DefNode) }
  enums.each { |node| converter.register_enum(node) }
  defs.each { |node| converter.register_function(node) }
  defs.each { |node| converter.lower_def(node) }
  converter
end

describe "enum carrier branch merges" do
  it "keeps a bitwise update and an unchanged enum in the named enum type" do
    converter = lower_enum_merge_source(<<-CRYSTAL)
      enum MergeFlags : UInt8
        A = 1
        B = 2
      end

      def strip_mask(options : MergeFlags, remove : Bool)
        if remove
          options &= ~MergeFlags::A
        end
        options
      end
    CRYSTAL
    function = converter.module.functions.find { |candidate| candidate.name.starts_with?("strip_mask") }.not_nil!
    instructions = function.blocks.flat_map(&.instructions)
    enum_phi = instructions.compact_map(&.as?(Adamas::HIR::Phi)).find do |phi|
      converter.module.get_type_descriptor(phi.type).try(&.name) == "MergeFlags"
    end
    enum_phi.should_not be_nil
    enum_phi = enum_phi.not_nil!
    enum_phi.incoming_values.each do |id|
      value = instructions.find { |instruction| instruction.id == id } ||
        function.params.find { |parameter| parameter.id == id }
      value = value.not_nil!
      value.type.should eq(enum_phi.type)
    end
    instructions.compact_map(&.as?(Adamas::HIR::UnionWrap)).none? do |wrap|
      converter.module.get_type_descriptor(wrap.type).try(&.name).try(&.includes?("MergeFlags"))
    end.should be_true
  end

  it "preserves an independent integer arm as a tagged union" do
    converter = lower_enum_merge_source(<<-CRYSTAL)
      enum MergeFlags : UInt8
        A = 1
      end

      def mixed_mask(value : MergeFlags, integer : Bool)
        if integer
          value = 1_u8
        end
        value
      end
    CRYSTAL
    function = converter.module.functions.find { |candidate| candidate.name.starts_with?("mixed_mask") }.not_nil!
    phis = function.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Phi))
    phis.any? do |phi|
      descriptor = converter.module.get_type_descriptor(phi.type)
      descriptor && descriptor.kind == Adamas::HIR::TypeKind::Union &&
        descriptor.name.includes?("MergeFlags") && descriptor.name.includes?("UInt8")
    end.should be_true
  end

  it "preserves a nil arm as a tagged union" do
    converter = lower_enum_merge_source(<<-CRYSTAL)
      enum MergeFlags : UInt8
        A = 1
      end

      def nullable_mask(value : MergeFlags, present : Bool)
        if present
          value
        else
          nil
        end
      end
    CRYSTAL
    function = converter.module.functions.find { |candidate| candidate.name.starts_with?("nullable_mask") }.not_nil!
    phis = function.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Phi))
    phis.any? do |phi|
      descriptor = converter.module.get_type_descriptor(phi.type)
      descriptor && descriptor.kind == Adamas::HIR::TypeKind::Union &&
        descriptor.name.includes?("MergeFlags") && descriptor.name.includes?("Nil")
    end.should be_true
  end
end
