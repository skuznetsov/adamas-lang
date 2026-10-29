require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

# Exercise the private yield-parameter inference entrypoint with deliberately
# conflicting name-level and ambient arena hints. The exact DefNode-to-arena
# association is the authority under test; ExprIds intentionally overlap.
class Adamas::HIR::AstToHir
  def __test_infer_yield_type_names_for_selected_definition(
    func_def : Adamas::Compiler::Frontend::DefNode,
    func_name : String,
    selected_arena : Adamas::Compiler::Frontend::ArenaLike,
    name_map_arena : Adamas::Compiler::Frontend::ArenaLike,
    ambient_arena : Adamas::Compiler::Frontend::ArenaLike,
    register_identity : Bool = true,
  ) : Array(String)?
    @def_node_arenas[func_def.object_id] = {func_def, selected_arena} if register_identity
    @function_def_arenas[func_name] = name_map_arena
    @arena = ambient_arena

    inferred = infer_yield_param_types_from_body(
      func_def,
      func_name,
      func_name,
      TypeRef::VOID,
      nil,
    )
    @arena.should be(ambient_arena)
    inferred.try &.map { |type_ref| get_type_name_from_ref(type_ref) }
  end
end

private def parse_yield_arena_provider(
  yielded_source : String,
) : {Adamas::Compiler::Frontend::ArenaLike, Adamas::Compiler::Frontend::DefNode}
  source = <<-CRYSTAL
    def yield_provider
      yield #{yielded_source}
    end
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty
  definition = program.roots
    .map { |root| program.arena[root].as?(Adamas::Compiler::Frontend::DefNode) }
    .compact
    .first
  definition.should_not be_nil
  {program.arena, definition.not_nil!}
end

describe "yield input inference arena identity" do
  it "uses the selected Def arena over stale same-name and ambient arenas" do
    arena_a, def_a = parse_yield_arena_provider("41")
    arena_b, def_b = parse_yield_arena_provider("\"B\"")

    # The separate parser arenas both start at index zero and have the same
    # shape. This makes an ambient-arena lookup observably select the other
    # arena's YieldNode/argument node, rather than merely exercising fallback.
    arena_a.size.should eq(arena_b.size)
    yielded_a = def_a.body.not_nil!.first
    yielded_b = def_b.body.not_nil!.first
    yielded_a.index.should eq(yielded_b.index)
    arena_a[yielded_a].as(Adamas::Compiler::Frontend::YieldNode).args.not_nil!.first.index
      .should eq(arena_b[yielded_b].as(Adamas::Compiler::Frontend::YieldNode).args.not_nil!.first.index)

    converter = Adamas::HIR::AstToHir.new(arena_a)
    converter.__test_infer_yield_type_names_for_selected_definition(
      def_a,
      "yield_provider",
      arena_a,
      arena_b,
      arena_b,
    ).should eq(["Int32"])
    converter.__test_infer_yield_type_names_for_selected_definition(
      def_b,
      "yield_provider",
      arena_b,
      arena_a,
      arena_a,
    ).should eq(["String"])
  end

  it "keeps the single-arena control unchanged" do
    arena, definition = parse_yield_arena_provider("41")
    converter = Adamas::HIR::AstToHir.new(arena)

    converter.__test_infer_yield_type_names_for_selected_definition(
      definition,
      "yield_provider",
      arena,
      arena,
      arena,
    ).should eq(["Int32"])
  end

  it "retains the valid arena hint for an unregistered definition" do
    arena, definition = parse_yield_arena_provider("41")
    converter = Adamas::HIR::AstToHir.new(arena)
    converter.__test_infer_yield_type_names_for_selected_definition(
      definition,
      "yield_provider",
      arena,
      arena,
      arena,
      register_identity: false,
    ).should eq(["Int32"])
  end
end
