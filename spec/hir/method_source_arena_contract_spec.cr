require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_method_source_arena_lower(
    owner : String,
    definition : Adamas::Compiler::Frontend::DefNode,
    source_arena : Adamas::Compiler::Frontend::ArenaLike,
    foreign_arena : Adamas::Compiler::Frontend::ArenaLike,
    foreign_definition : Adamas::Compiler::Frontend::DefNode,
    method : String,
    conflicting_physical : Bool = false,
    missing_physical_arena : Bool = false,
    generated_source : Bool = false,
    invalid_registered_arena : Bool = false,
  ) : Tuple(Bool, Array(Int64))
    base = "#{owner}##{method}"
    physical = "#{base}$Int32__source_arena_probe"

    # The physical symbol selects this exact source Def. The bare alias is
    # deliberately assigned to a sibling Def from another arena.
    set_function_def_entry(physical, definition, record_current_arena: false)
    set_function_def_arena(physical, source_arena)
    set_function_def_entry(base, foreign_definition, record_current_arena: false)
    set_function_def_arena(base, foreign_arena)

    # Simulate a stale physical symbol-to-arena hint without changing the exact
    # Def-to-arena ownership record established above.
    @function_def_arenas[physical] = foreign_arena if conflicting_physical
    @function_def_arenas.delete(physical) if missing_physical_arena || generated_source
    if invalid_registered_arena
      set_function_def_arena(physical, Adamas::Compiler::Frontend::AstArena.new)
    end

    # A foreign active arena makes fallback selection observable when the
    # physical specialization has no arena entry.
    context_arena = missing_physical_arena || generated_source ? foreign_arena : source_arena
    with_arena(context_arena) do
      lower_method(owner, @class_info[owner], definition, full_name_override: physical)
    end

    function = @module.function_by_name(physical).not_nil!
    literals = function.blocks.flat_map do |block|
      block.instructions.compact_map do |instruction|
        instruction.as?(Literal).try(&.value.as?(Int64))
      end
    end
    {!function.blocks.empty?, literals}
  end
end

private def method_source_arena_fixture(generated_source : Bool = false)
  source = <<-CRYSTAL
    class MethodSourceArenaOwner
      def value
        65
      end
    end
    CRYSTAL
  foreign_source = source.gsub("65", "66")

  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  parsed = parser.parse_program
  parser.diagnostics.should be_empty

  foreign_parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(foreign_source))
  foreign = foreign_parser.parse_program
  foreign_parser.diagnostics.should be_empty

  arena = parsed.ast_arena
  foreign_arena = foreign.ast_arena
  converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {
    arena.object_id.to_u64         => (generated_source ? "" : source),
    foreign_arena.object_id.to_u64 => foreign_source,
  })
  converter.no_prelude = true

  owner = arena[parsed.roots.first].as(Adamas::Compiler::Frontend::ClassNode)
  definition = owner.body.not_nil!.compact_map do |id|
    arena[id].as?(Adamas::Compiler::Frontend::DefNode)
  end.first

  foreign_owner = foreign_arena[foreign.roots.first].as(Adamas::Compiler::Frontend::ClassNode)
  foreign_definition = foreign_owner.body.not_nil!.compact_map do |id|
    foreign_arena[id].as?(Adamas::Compiler::Frontend::DefNode)
  end.first

  converter.register_class(owner)
  {converter, definition, arena, foreign_arena, foreign_definition}
end

describe "method declaration arena ownership" do
  it "uses the selected Def arena when a bare method alias points at a sibling" do
    converter, definition, arena, foreign_arena, foreign_definition = method_source_arena_fixture
    body_exists, literals = converter.__test_method_source_arena_lower(
      "MethodSourceArenaOwner", definition, arena, foreign_arena, foreign_definition, "value",
      missing_physical_arena: true
    )
    body_exists.should be_true
    literals.should contain(65_i64)
    literals.should_not contain(66_i64)
  end

  it "uses the exact Def arena over a conflicting physical arena hint" do
    converter, definition, arena, foreign_arena, foreign_definition = method_source_arena_fixture
    body_exists, literals = converter.__test_method_source_arena_lower(
      "MethodSourceArenaOwner", definition, arena, foreign_arena, foreign_definition, "value",
      conflicting_physical: true
    )
    body_exists.should be_true
    literals.should contain(65_i64)
    literals.should_not contain(66_i64)
  end

  it "keeps an exact registered generated body when its span exceeds the primary buffer" do
    converter, definition, arena, foreign_arena, foreign_definition = method_source_arena_fixture(generated_source: true)
    body_exists, literals = converter.__test_method_source_arena_lower(
      "MethodSourceArenaOwner", definition, arena, foreign_arena, foreign_definition, "value",
      generated_source: true
    )
    body_exists.should be_true
    literals.should contain(65_i64)
    literals.should_not contain(66_i64)
  end

  it "rejects an exact registered arena that cannot contain the body ExprIds" do
    converter, definition, arena, foreign_arena, foreign_definition = method_source_arena_fixture
    expect_raises(Adamas::HIR::LoweringError, "registered method source body exceeds its arena") do
      converter.__test_method_source_arena_lower(
        "MethodSourceArenaOwner", definition, arena, foreign_arena, foreign_definition, "value",
        invalid_registered_arena: true
      )
    end
  end
end
