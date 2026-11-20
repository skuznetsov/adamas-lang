require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_forwarded_yield_stability(
    expr : Adamas::Compiler::Frontend::ExprId,
    stable_indices : Array(Int32),
    local_input_indices : Hash(String, Array(Int32)),
  ) : Array(Int32)
    input = SourceCallArgument.new(TypeRef::INT32, false)
    source = InlineCallbackSourceWitness.new([input, input], input, stable_indices)
    locals = local_input_indices.transform_values { |indices| InlineCallbackExpressionWitness.new(input, indices) }
    function = @module.create_function("__forwarded_yield_probe", TypeRef::VOID)
    ctx = LoweringContext.new(function, @module, @arena)
    witness = inline_block_source_witness_for_expr(ctx, expr, locals, nil, source) ||
              raise "expected a source result for the forwarded yield"
    witness.fixed_initializer_leaves
  end

  def __test_block_result_stability(
    definition : Adamas::Compiler::Frontend::DefNode,
    block : Adamas::Compiler::Frontend::BlockNode,
  ) : Tuple(Array(Int32), Bool)?
    function = @module.create_function("__callback_result_probe", TypeRef::VOID)
    ctx = LoweringContext.new(function, @module, @arena)
    owner = BlockOwner.new(nil, nil, false, method_source_yield_context(definition, @arena))
    witness = inline_block_return_source_witness(ctx, block, @arena, definition, @arena, nil,
      {} of String => String, owner, {} of String => String) || return nil
    {witness.subtype_stable_input_indices, inline_callback_forward_source_inputs_stable?(witness)}
  end
end

private def forwarded_yield_stability_expr(source : String)
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(program.arena)
  definition = program.roots.compact_map do |root|
    program.arena[root].as?(Adamas::Compiler::Frontend::DefNode)
  end.first? || raise "expected a source method"
  yield_expr = definition.body.not_nil!.find do |expr|
    program.arena[expr].is_a?(Adamas::Compiler::Frontend::YieldNode)
  end || raise "expected a yield expression"
  {converter, yield_expr}
end

private def callback_result_stability(tail : String, extra_initializers : String = "")
  source = <<-CRYSTAL
    abstract class ProofValue
    end
    class ProofEntry < ProofValue
      def initialize(@value : ProofValue)
      end
      #{extra_initializers}
    end
    class ProofKey < ProofValue
      def initialize(@name : String)
      end
    end
    def probe(& : String, ProofValue -> U) : U forall U
    end
    probe do |label, argument|
      checked = ProofEntry.new(argument).as(ProofValue)
      #{tail}
    end
    CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
  definition = nil.as(Adamas::Compiler::Frontend::DefNode?)
  block = nil.as(Adamas::Compiler::Frontend::BlockNode?)
  program.roots.each do |id|
    case node = arena[id]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::DefNode
      definition = node
    when Adamas::Compiler::Frontend::CallNode
      block = arena[node.block.not_nil!].as(Adamas::Compiler::Frontend::BlockNode)
    end
  end
  converter.__test_block_result_stability(definition.not_nil!, block.not_nil!)
end

describe "forwarded callback subtype stability lineage" do
  it "translates a stable source slot through a same-typed permutation" do
    converter, expr = forwarded_yield_stability_expr("def probe\n  yield second, first\nend\n")
    converter.__test_forwarded_yield_stability(
      expr, [0], {"first" => [0], "second" => [1]},
    ).should eq([1])
  end

  it "does not assign a stable slot to a same-typed literal" do
    converter, expr = forwarded_yield_stability_expr("def probe\n  yield 0, second\nend\n")
    converter.__test_forwarded_yield_stability(
      expr, [0], {"first" => [0], "second" => [1]},
    ).should be_empty
  end

  it "uses the returned local's proof and discards an unrelated prefix proof" do
    callback_result_stability("(checked)").should eq({[1], true})
    callback_result_stability("ProofKey.new(label).as(ProofValue)").should eq({[] of Int32, false})
  end

  it "does not reuse a fixed nominal result when another initializer can select by subtype" do
    overload = <<-CRYSTAL
      def initialize(@value : ProofEntry)
      end
      CRYSTAL
    callback_result_stability("(checked)", overload).should be_nil
  end
end
