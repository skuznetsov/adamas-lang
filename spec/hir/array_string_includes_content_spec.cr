require "spec"
require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_array_includes_content_program(
  source : String,
) : {Adamas::HIR::AstToHir, Hash(String, Adamas::HIR::Function)}
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source)
  )
  result = parser.parse_program
  raise "parser diagnostics: #{parser.diagnostics.size}" unless parser.diagnostics.empty?

  converter = Adamas::HIR::AstToHir.new(
    result.arena,
    sources_by_arena: {result.arena.object_id.to_u64 => source},
  )
  converter.arena = result.arena

  defs = result.roots.compact_map do |expr_id|
    result.arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode)
  end
  defs.each { |definition| converter.register_function(definition) }

  functions = {} of String => Adamas::HIR::Function
  defs.each do |definition|
    name = String.new(definition.name.not_nil!)
    functions[name] = converter.lower_def(definition)
  end
  {converter, functions}
end

describe "dynamic Array#includes? equality lowering" do
  it "uses content equality for String elements" do
    _, functions = lower_array_includes_content_program(<<-CRYSTAL)
      def string_probe(values : Array(String), needle : String) : Bool
        values.includes?(needle)
      end
    CRYSTAL

    instructions = functions["string_probe"].blocks.flat_map(&.instructions)
    string_calls = instructions.compact_map do |instruction|
      instruction.as?(Adamas::HIR::Call)
    end.select { |call| call.method_name == "__adamas_string_eq" }
    string_calls.size.should eq(1)
    string_calls.first.type.should eq(Adamas::HIR::TypeRef::BOOL)
    string_calls.first.args.size.should eq(1)

    instructions.compact_map { |instruction| instruction.as?(Adamas::HIR::BinaryOperation) }
      .none? { |operation| operation.op == Adamas::HIR::BinaryOp::Eq }
      .should be_true
  end

  it "keeps primitive element equality on the binary operation path" do
    _, functions = lower_array_includes_content_program(<<-CRYSTAL)
      def int_probe(values : Array(Int32), needle : Int32) : Bool
        values.includes?(needle)
      end
    CRYSTAL

    instructions = functions["int_probe"].blocks.flat_map(&.instructions)
    instructions.compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .none? { |call| call.method_name == "__adamas_string_eq" }
      .should be_true

    eq_operations = instructions.compact_map do |instruction|
      instruction.as?(Adamas::HIR::BinaryOperation)
    end.select { |operation| operation.op == Adamas::HIR::BinaryOp::Eq }
    eq_operations.size.should eq(1)
    eq_operations.first.type.should eq(Adamas::HIR::TypeRef::BOOL)
  end
end
