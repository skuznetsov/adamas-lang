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
  classes = result.roots.compact_map { |id| result.arena[id].as?(Adamas::Compiler::Frontend::ClassNode) }
  defs = result.roots.compact_map { |id| result.arena[id].as?(Adamas::Compiler::Frontend::DefNode) }
  enums.each { |node| converter.register_enum(node) }
  classes.each { |node| converter.register_class(node) }
  defs.each { |node| converter.register_function(node) }
  classes.each { |node| converter.lower_class(node) }
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

  it "preserves one enum identity through case-local merging into a constructor" do
    converter = lower_enum_merge_source(<<-CRYSTAL)
      enum LexerTokenKind
        String
        Array
        Regex
      end

      class LexerToken
        def initialize(kind : LexerTokenKind)
        end
      end

      def token_after_case(selector : Int32)
        literal_type = LexerTokenKind::String
        case selector
        when 1
          literal_type = LexerTokenKind::Array
        when 2
          literal_type = LexerTokenKind::Regex
        end
        LexerToken.new(literal_type)
      end
    CRYSTAL

    function = converter.module.functions.find do |candidate|
      candidate.name.starts_with?("token_after_case$")
    end
    function.should_not be_nil
    constructor_call = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |call| call.method_name.starts_with?("LexerToken.new") }
    constructor_call.should_not be_nil
    allocator = converter.module.function_by_name(constructor_call.not_nil!.method_name)
    allocator.should_not be_nil
    initializer = allocator.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |call| call.method_name.starts_with?("LexerToken#initialize") }
    initializer.should_not be_nil
    initializer.not_nil!.method_name.should eq(
      "LexerToken#initialize$LexerTokenKind",
    )
  end

  it "retains each case-local union alternative when only some share a carrier" do
    converter = lower_enum_merge_source(<<-CRYSTAL)
      enum LexerTokenKind
        String = 11
      end

      enum OtherTokenKind
        Other = 22
      end

      enum ByteTokenKind : UInt8
        Byte = 33
      end

      def value_after_mixed_case(selector : Int32)
        value = LexerTokenKind::String
        case selector
        when 1
          value = OtherTokenKind::Other
        when 2
          value = ByteTokenKind::Byte
        when 3
          value = 44
        end
        value
      end
    CRYSTAL

    function = converter.module.functions.find do |candidate|
      candidate.name.starts_with?("value_after_mixed_case$")
    end
    function.should_not be_nil
    function = function.not_nil!
    return_type = converter.module.get_type_descriptor(function.return_type)
    return_type.should_not be_nil
    return_type = return_type.not_nil!
    return_type.kind.should eq(Adamas::HIR::TypeKind::Union)
    union_descriptor = converter.union_descriptors.values.find do |descriptor|
      descriptor.name == return_type.name
    end
    union_descriptor.should_not be_nil

    variants = union_descriptor.not_nil!.variants
    variants.map(&.full_name).to_set.should eq(Set{
      "ByteTokenKind",
      "Int32",
      "LexerTokenKind",
      "OtherTokenKind",
    })

    instructions = function.blocks.flat_map(&.instructions)
    phis = instructions.compact_map(&.as?(Adamas::HIR::Phi)).select do |phi|
      phi.type == function.return_type && phi.incoming_values.all? do |value_id|
        instructions.any? { |instruction| instruction.id == value_id && instruction.is_a?(Adamas::HIR::UnionWrap) }
      end
    end
    phis.should_not be_empty
    return_ids = function.blocks.compact_map(&.terminator.as?(Adamas::HIR::Return)).compact_map(&.value)
    return_roots = [] of Adamas::HIR::ValueId
    return_ids.each do |return_id|
      root = return_id
      loop do
        copy = instructions.find { |instruction| instruction.id == root }.as?(Adamas::HIR::Copy)
        break unless copy
        root = copy.source
      end
      return_roots << root
    end
    phis.any? { |phi| return_roots.includes?(phi.id) }.should be_true
    wraps = phis.flat_map do |phi|
      phi.incoming_values.compact_map do |value_id|
        instructions.find { |instruction| instruction.id == value_id }.as?(Adamas::HIR::UnionWrap)
      end
    end
    wrapped_values = wraps.to_h do |wrap|
      payload = instructions.find { |instruction| instruction.id == wrap.value }
      while copy = payload.as?(Adamas::HIR::Copy)
        payload = instructions.find { |instruction| instruction.id == copy.source }
      end
      payload.should be_a(Adamas::HIR::Literal)
      variant = variants.find { |candidate| candidate.type_id == wrap.variant_type_id }
      variant.should_not be_nil
      {payload.as(Adamas::HIR::Literal).int_value, variant.not_nil!.full_name}
    end
    wrapped_values[11_i64].should eq("LexerTokenKind")
    wrapped_values[22_i64].should eq("OtherTokenKind")
    wrapped_values[33_i64].should eq("ByteTokenKind")
    wrapped_values[44_i64].should eq("Int32")
  end
end
