require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def array_union_carrier_function(source : String)
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(program.arena,
    sources_by_arena: {program.arena.object_id.to_u64 => source})
  converter.no_prelude = true
  defs = [] of Adamas::Compiler::Frontend::DefNode
  program.roots.each do |root|
    case node = program.arena[root]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
      defs << node
    end
  end
  defs.each { |node| converter.lower_def(node) }
  converter.module.functions.find { |function| function.name.starts_with?("build_array_carriers") }.not_nil!
end

describe "Union carriers in array literals" do
  it "wraps a concrete struct before the array consumes its opaque MIR allocation" do
    function = array_union_carrier_function(<<-CRYSTAL)
      struct ArrayCarrierStart; end
      struct ArrayCarrierEnd; end
      def build_array_carriers(value : ArrayCarrierStart)
        [value] of ArrayCarrierStart | ArrayCarrierEnd
      end
    CRYSTAL
    instructions = function.blocks.flat_map(&.instructions)
    array = instructions.select(Adamas::HIR::ArrayLiteral).first
    element = instructions.find { |instruction| instruction.id == array.elements.first }.not_nil!
    element.should be_a(Adamas::HIR::UnionWrap)
    wrap = element.as(Adamas::HIR::UnionWrap)
    wrap.type.should eq(array.element_type)
    wrap.variant_type_id.should be >= 0
    input = instructions.find { |instruction| instruction.id == wrap.value }.not_nil!
    input.as(Adamas::HIR::Copy).source.should eq(function.params.first.id)
  end

  it "retains the existing union carrier without wrapping it twice" do
    function = array_union_carrier_function(<<-CRYSTAL)
      struct ArrayCarrierStart; end
      struct ArrayCarrierEnd; end
      def build_array_carriers(value : ArrayCarrierStart | ArrayCarrierEnd)
        [value] of ArrayCarrierStart | ArrayCarrierEnd
      end
    CRYSTAL
    instructions = function.blocks.flat_map(&.instructions)
    array = instructions.select(Adamas::HIR::ArrayLiteral).first
    array.element_type.should eq(function.params.first.type)
    input = instructions.find { |instruction| instruction.id == array.elements.first }.not_nil!
    input.as(Adamas::HIR::Copy).source.should eq(function.params.first.id)
    instructions.select(Adamas::HIR::UnionWrap).should be_empty
  end
end
