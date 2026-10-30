require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_yield_return_source_arena(
    definition : Adamas::Compiler::Frontend::DefNode,
    definition_arena : Adamas::Compiler::Frontend::ArenaLike,
    stale_hint : Adamas::Compiler::Frontend::ArenaLike,
    block : Adamas::Compiler::Frontend::BlockNode,
    block_arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Bool
    @def_node_arenas[definition.object_id] = {definition, definition_arena}
    @arena = stale_hint
    function = @module.create_function("__yield_return_source_arena", TypeRef::NIL)
    captured = function.add_param("captured", TypeRef::INT32)
    ctx = LoweringContext.new(function, @module, stale_hint)
    ctx.register_local("captured", captured.id)
    ctx.register_type(captured.id, TypeRef::INT32)
    result = yield_return_requires_block_fallback?(ctx, definition, stale_hint, block, block_arena)
    @arena.should be(stale_hint)
    result
  end
end

private def parse_yield_return_source(source : String)
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  program
end

private def yield_return_source_fixture(stale_source : String, shadow : Bool = false)
  provider = parse_yield_return_source(<<-CRYSTAL)
    def provide(flag)
      return if flag
      yield
    end
  CRYSTAL
  definition = provider.arena[provider.roots.first].as(Adamas::Compiler::Frontend::DefNode)
  caller = parse_yield_return_source(shadow ? "provide { |captured| captured = 1 }" : "provide { captured = 1 }")
  call = caller.arena[caller.roots.first].as(Adamas::Compiler::Frontend::CallNode)
  block = caller.arena[call.block.not_nil!].as(Adamas::Compiler::Frontend::BlockNode)
  stale = parse_yield_return_source(stale_source)
  converter = Adamas::HIR::AstToHir.new(provider.arena)
  converter.__test_yield_return_source_arena(definition, provider.arena, stale.arena, block, caller.arena)
end

describe "yield return source arena authority" do
  it "checks early returns in the selected Def arena when the name hint is too small" do
    yield_return_source_fixture("0").should be_true
  end

  it "does not interpret colliding foreign expression indices as the selected body" do
    yield_return_source_fixture(<<-CRYSTAL).should be_true
      def provide(flag)
        0 if flag
        yield
      end
    CRYSTAL
  end

  it "keeps block parameter shadowing local to the block arena" do
    yield_return_source_fixture("0", shadow: true).should be_false
  end
end
