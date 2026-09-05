require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

private def lower_tuple_return_scope(code : String)
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(code))
  parsed = parser.parse_program
  converter = Adamas::HIR::AstToHir.new(parsed.arena)
  definitions = parsed.roots.compact_map { |id| parsed.arena[id].as?(Adamas::Compiler::Frontend::DefNode) }
  definitions.each { |node| converter.register_function(node) }
  functions = definitions.map { |node| converter.lower_def(node) }
  {converter.module, functions}
end

describe "tuple literal return scope" do
  it "retains local tuple element types despite an equal-arity declared return" do
    hir_module, functions = lower_tuple_return_scope(<<-CRYSTAL)
      def probe(left : String, right : String) : {Int32, Int32}
        key = {left, right}
        {1, 2}
      end
      CRYSTAL
    allocations = functions.first.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Allocate))
    descriptor = hir_module.get_type_descriptor(allocations.first.type).not_nil!
    descriptor.type_params.should eq([Adamas::HIR::TypeRef::STRING, Adamas::HIR::TypeRef::STRING])
    allocations.last.type.should eq(functions.first.return_type)
  end

  [false, true].each do |explicit|
    it "coerces nullable tuple elements at the #{explicit ? "explicit" : "implicit"} return" do
      hir_module, functions = lower_tuple_return_scope(<<-CRYSTAL)
        def probe : {Int32?, Int32?}
          #{explicit ? "return " : ""}{nil, 1}
        end
        CRYSTAL
      function = functions.first
      instructions = function.blocks.flat_map(&.instructions)
      returns = function.blocks.compact_map(&.terminator.as?(Adamas::HIR::Return))
      returned = returns.compact_map do |ret|
        instructions.find { |instruction| instruction.id == ret.value }
      end
      returned.should_not be_empty
      returned.each { |instruction| instruction.type.should eq(function.return_type) }
      instructions.count(&.is_a?(Adamas::HIR::UnionWrap)).should be >= 2
      hir_module.get_type_descriptor(function.return_type).not_nil!.type_params.size.should eq(2)
    end
  end
end
