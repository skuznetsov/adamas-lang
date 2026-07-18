require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_arena_identity_id(
    arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Adamas::Compiler::Semantic::ArenaId
    arena_identity_registry!.id_for(arena)
  end

  def __test_register_function_def_arena(
    name : String,
    arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Bool
    set_function_def_arena(name, arena)
    arena_identity_registry!.registered?(arena)
  end

  def __test_arena_identity_registry_initialized? : Bool
    !@arena_identity_registry.nil?
  end

  def __test_def_identity_for_provenance(
    node : Adamas::Compiler::Frontend::DefNode,
    resolved_arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Adamas::Compiler::Semantic::DefIdentity?
    canonical_def_identity_for_provenance(node, resolved_arena)
  end
end

private def parse_provenance_program(
  code : String,
) : {Adamas::Compiler::Frontend::ArenaLike, Array(Adamas::Compiler::Frontend::ExprId)}
  lexer = Adamas::Compiler::Frontend::Lexer.new(code)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  {result.arena, result.roots}
end

private def first_provenance_def(
  arena : Adamas::Compiler::Frontend::ArenaLike,
  exprs : Array(Adamas::Compiler::Frontend::ExprId),
) : {Adamas::Compiler::Frontend::ExprId, Adamas::Compiler::Frontend::DefNode}
  expr_id = exprs.find { |candidate| arena[candidate].is_a?(Adamas::Compiler::Frontend::DefNode) }
  raise "No function definition found" unless expr_id
  {expr_id, arena[expr_id].as(Adamas::Compiler::Frontend::DefNode)}
end

describe Adamas::HIR::AstToHir do
  it "registers distinct owner arenas without using the owner address as identity" do
    code_a = <<-CRYSTAL
      def sample_a(value : Int32)
        value + 1
      end
    CRYSTAL
    code_b = <<-CRYSTAL
      def sample_b(value : Int32)
        value + 1
      end
    CRYSTAL
    arena_a, exprs_a = parse_provenance_program(code_a)
    arena_b, exprs_b = parse_provenance_program(code_b)

    previous_assert = ENV["ADAMAS_RESOLUTION_ASSERT"]?
    ENV["ADAMAS_RESOLUTION_ASSERT"] = "1"
    begin
      converter = Adamas::HIR::AstToHir.new(
        arena_a,
        sources_by_arena: {arena_a.object_id => code_a, arena_b.object_id => code_b},
        paths_by_arena: {arena_a.object_id => "/tmp/provenance_a.cr", arena_b.object_id => "/tmp/provenance_b.cr"},
        main_arenas: [arena_a, arena_b],
      )

      converter.__test_register_function_def_arena("sample_a", arena_a).should be_true
      converter.__test_register_function_def_arena("sample_b", arena_b).should be_true
      id_a = converter.__test_arena_identity_id(arena_a)
      id_b = converter.__test_arena_identity_id(arena_b)

      id_a.should_not eq(id_b)
      id_a.should eq(converter.__test_arena_identity_id(arena_a))
      id_a.value.should_not eq(arena_a.object_id.to_u64)

      expr_id, def_node = first_provenance_def(arena_a, exprs_a)
      identity = converter.__test_def_identity_for_provenance(def_node, arena_a)
      identity.should_not be_nil
      identity = identity.not_nil!
      identity.arena_id.should eq(id_a.value)
      identity.expr_index.should eq(expr_id.index)

      expr_id_b, def_b = first_provenance_def(arena_b, exprs_b)
      identity_b = converter.__test_def_identity_for_provenance(def_b, arena_b)
      identity_b.should_not be_nil
      identity_b = identity_b.not_nil!
      identity_b.expr_index.should eq(expr_id_b.index)
      identity_b.expr_index.should eq(identity.expr_index)
      identity_b.arena_id.should_not eq(identity.arena_id)
    ensure
      if previous_assert
        ENV["ADAMAS_RESOLUTION_ASSERT"] = previous_assert
      else
        ENV.delete("ADAMAS_RESOLUTION_ASSERT")
      end
    end
  end

  it "does not allocate the candidate registry when assertion is disabled" do
    previous_assert = ENV["ADAMAS_RESOLUTION_ASSERT"]?
    ENV.delete("ADAMAS_RESOLUTION_ASSERT")
    begin
      arena = Adamas::Compiler::Frontend::AstArena.new
      converter = Adamas::HIR::AstToHir.new(arena, main_arenas: [arena])
      converter.__test_arena_identity_registry_initialized?.should be_false
    ensure
      if previous_assert
        ENV["ADAMAS_RESOLUTION_ASSERT"] = previous_assert
      else
        ENV.delete("ADAMAS_RESOLUTION_ASSERT")
      end
    end
  end

  it "fails closed when one owner contains duplicate structural matches" do
    code = <<-CRYSTAL
      def sample(value : Int32)
        value + 1
      end
    CRYSTAL
    arena, exprs = parse_provenance_program(code)
    _expr_id, def_node = first_provenance_def(arena, exprs)
    arena.add(def_node)

    converter = Adamas::HIR::AstToHir.new(
      arena,
      sources_by_arena: {arena.object_id => code},
      paths_by_arena: {arena.object_id => "/tmp/provenance_duplicate.cr"},
      main_arenas: [arena],
    )

    converter.__test_def_identity_for_provenance(def_node, arena).should be_nil
  end

  it "fails closed when identical definitions exist in two owner arenas" do
    code = <<-CRYSTAL
      def sample(value : Int32)
        value + 1
      end
    CRYSTAL
    arena_a, exprs_a = parse_provenance_program(code)
    arena_b, _exprs_b = parse_provenance_program(code)
    _expr_id, def_node = first_provenance_def(arena_a, exprs_a)

    converter = Adamas::HIR::AstToHir.new(
      arena_a,
      sources_by_arena: {arena_a.object_id => code, arena_b.object_id => code},
      paths_by_arena: {arena_a.object_id => "/tmp/provenance_same_a.cr", arena_b.object_id => "/tmp/provenance_same_b.cr"},
      main_arenas: [arena_a, arena_b],
    )

    converter.__test_def_identity_for_provenance(def_node, arena_a).should be_nil
  end

  it "fails closed when the selected owner has no matching definition" do
    code = <<-CRYSTAL
      def sample(value : Int32)
        value + 1
      end
    CRYSTAL
    source_arena, exprs = parse_provenance_program(code)
    _expr_id, def_node = first_provenance_def(source_arena, exprs)
    empty_arena = Adamas::Compiler::Frontend::AstArena.new

    converter = Adamas::HIR::AstToHir.new(
      empty_arena,
      sources_by_arena: {empty_arena.object_id => ""},
      paths_by_arena: {empty_arena.object_id => "/tmp/provenance_empty.cr"},
      main_arenas: [empty_arena],
    )

    converter.__test_def_identity_for_provenance(def_node, empty_arena).should be_nil
  end
end
