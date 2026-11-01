require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_register_exact_source_owner(
    name : String,
    definition : Adamas::Compiler::Frontend::DefNode,
    arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Nil
    @function_defs[name] = definition
    set_function_def_arena(name, arena)
  end

  def __test_recover_source_def(
    definition : Adamas::Compiler::Frontend::DefNode,
    arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Adamas::Compiler::Frontend::DefNode?
    source_recovered_def_for(definition, arena)
  end

  def __test_infer_registered_default_type(
    default_expr : Adamas::Compiler::Frontend::ExprId,
    runtime_owner : String,
    definition : Adamas::Compiler::Frontend::DefNode,
    logical_name : String,
    fallback_arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Adamas::HIR::TypeRef?
    infer_registered_method_default_type(
      default_expr,
      runtime_owner,
      definition,
      logical_name,
      fallback_arena,
      nil,
    )
  end

  def __test_registered_body_owner?(
    body : Array(Adamas::Compiler::Frontend::ExprId),
    expected : Adamas::Compiler::Frontend::ArenaLike,
  ) : Bool
    owner = registered_arena_for_body(body)
    !!owner && owner.not_nil!.same?(expected)
  end

  def __test_registered_def_owner?(
    definition : Adamas::Compiler::Frontend::DefNode,
  ) : Bool
    !registered_arena_for_def(definition).nil?
  end

  def __test_arena_fits_def?(
    arena : Adamas::Compiler::Frontend::ArenaLike,
    definition : Adamas::Compiler::Frontend::DefNode,
  ) : Bool
    arena_fits_def?(arena, definition)
  end

  def __test_resolve_arena_for_def(
    definition : Adamas::Compiler::Frontend::DefNode,
    fallback : Adamas::Compiler::Frontend::ArenaLike,
  ) : Adamas::Compiler::Frontend::ArenaLike
    resolve_arena_for_def(definition, fallback)
  end

  def __test_canonical_arena_for_def(
    definition : Adamas::Compiler::Frontend::DefNode,
    fallback : Adamas::Compiler::Frontend::ArenaLike,
  ) : Adamas::Compiler::Frontend::ArenaLike
    canonical_arena_for_def(definition, fallback)
  end
end

private def parse_recovered_arena_source(
  source : String,
) : {Adamas::Compiler::Frontend::ArenaLike, Array(Adamas::Compiler::Frontend::ExprId)}
  lexer = Adamas::Compiler::Frontend::Lexer.new(source)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  {result.arena, result.roots}
end

private def recovered_arena_source(literal : String) : String
  <<-CRYSTAL
    def recoverable(value : Int32)
      #{literal}
    end
  CRYSTAL
end

private def recovered_arena_default_source(default_literal : String) : String
  <<-CRYSTAL
    def recoverable(value = #{default_literal})
      value
    end
  CRYSTAL
end

private def recovered_arena_definition(
  arena : Adamas::Compiler::Frontend::ArenaLike,
  roots : Array(Adamas::Compiler::Frontend::ExprId),
) : Adamas::Compiler::Frontend::DefNode
  roots.each do |expr_id|
    if definition = arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode)
      return definition if String.new(definition.name) == "recoverable"
    end
  end
  raise "missing recoverable DefNode"
end

private def recovered_arena_body_literal(
  arena : Adamas::Compiler::Frontend::ArenaLike,
  definition : Adamas::Compiler::Frontend::DefNode,
) : Int64
  body = definition.body || raise "missing body"
  number = arena[body.first].as(Adamas::Compiler::Frontend::NumberNode)
  number.parsed_int
end

describe "source-recovered Def arena identity" do
  it "keeps recovered default ExprIds paired with their exact arena" do
    owner_source = recovered_arena_default_source("65_i32")
    foreign_source = recovered_arena_default_source("65_i64")
    owner_arena, owner_roots = parse_recovered_arena_source(owner_source)
    foreign_arena, foreign_roots = parse_recovered_arena_source(foreign_source)
    owner_def = recovered_arena_definition(owner_arena, owner_roots)
    foreign_def = recovered_arena_definition(foreign_arena, foreign_roots)
    owner_def.span.should eq(foreign_def.span)
    owner_def.params.not_nil!.clear

    # Give the foreign recovered default's ExprId a valid, conflicting node in
    # the registered owner arena. Range checks alone must not admit this value.
    padding_parser = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new("77_i16"), owner_arena,
    )
    padding = padding_parser.parse_program

    converter = Adamas::HIR::AstToHir.new(
      foreign_arena,
      sources_by_arena: {
        owner_arena.object_id.to_u64 => owner_source,
        foreign_arena.object_id.to_u64 => foreign_source,
      },
      main_arenas: [foreign_arena, owner_arena],
    )
    converter.__test_register_exact_source_owner("recoverable", owner_def, owner_arena)

    recovered = converter.__test_recover_source_def(owner_def, foreign_arena)
    recovered.should_not be_nil
    recovered = recovered.not_nil!
    default_expr = recovered.params.not_nil!.first.default_value.not_nil!
    default_expr.index.should eq(padding.roots.first.index)
    owner_arena[default_expr].as(Adamas::Compiler::Frontend::NumberNode).parsed_int.should eq(77)

    # The recovered Parameter and its default ExprId came from the foreign
    # arena, while the registered source declaration belongs to owner_arena.
    # Inference must reject this mismatch before indexing either arena.
    converter.__test_infer_registered_default_type(
      default_expr,
      "RecoverableOwner",
      recovered,
      "recoverable",
      owner_arena,
    ).should be_nil
    converter.__test_recover_source_def(owner_def, owner_arena).should be_nil
  end

  it "infers a recovered default when its execution and registered arenas match" do
    owner_source = recovered_arena_default_source("65_i32")
    owner_arena, owner_roots = parse_recovered_arena_source(owner_source)
    owner_def = recovered_arena_definition(owner_arena, owner_roots)
    owner_def.params.not_nil!.clear

    converter = Adamas::HIR::AstToHir.new(
      owner_arena,
      sources_by_arena: {owner_arena.object_id.to_u64 => owner_source},
      main_arenas: [owner_arena],
    )
    converter.__test_register_exact_source_owner("recoverable", owner_def, owner_arena)

    recovered = converter.__test_recover_source_def(owner_def, owner_arena).not_nil!
    default_expr = recovered.params.not_nil!.first.default_value.not_nil!
    inferred = converter.__test_infer_registered_default_type(
      default_expr,
      "RecoverableOwner",
      recovered,
      "recoverable",
      owner_arena,
    )
    inferred.should eq(Adamas::HIR::TypeRef::INT32)
  end

  it "prefers the exact retained body owner over a same-shape fallback arena" do
    owner_source = recovered_arena_source("65")
    foreign_source = recovered_arena_source("66")
    owner_arena, owner_roots = parse_recovered_arena_source(owner_source)
    foreign_arena, foreign_roots = parse_recovered_arena_source(foreign_source)
    owner_def = recovered_arena_definition(owner_arena, owner_roots)
    foreign_def = recovered_arena_definition(foreign_arena, foreign_roots)

    owner_def.span.should eq(foreign_def.span)
    owner_arena.size.should eq(foreign_arena.size)
    recovered_arena_body_literal(owner_arena, owner_def).should eq(65_i64)
    recovered_arena_body_literal(foreign_arena, foreign_def).should eq(66_i64)

    # Empty parameter storage is the source-backed self-host recovery case.
    # Preserve the body Array and its original ExprIds while forcing only the
    # header to be reconstructed from the exact source owner.
    owner_def.params.not_nil!.clear
    converter = Adamas::HIR::AstToHir.new(
      foreign_arena,
      sources_by_arena: {
        owner_arena.object_id.to_u64 => owner_source,
        foreign_arena.object_id.to_u64 => foreign_source,
      },
      main_arenas: [foreign_arena, owner_arena],
    )
    converter.__test_register_exact_source_owner("recoverable", owner_def, owner_arena)

    recovered = converter.__test_recover_source_def(owner_def, owner_arena)
    recovered.should_not be_nil
    recovered = recovered.not_nil!
    recovered.same?(owner_def).should be_false
    recovered.body.should_not be_nil
    recovered.body.not_nil!.same?(owner_def.body.not_nil!).should be_true

    # A recovered clone has no Def-object registration, but its shared body
    # identity still names the original arena. Both arenas structurally fit,
    # so choosing the caller fallback would attach the same ExprIds to a
    # different literal payload.
    converter.__test_registered_def_owner?(recovered).should be_false
    converter.__test_registered_body_owner?(recovered.body.not_nil!, owner_arena).should be_true
    converter.__test_arena_fits_def?(owner_arena, recovered).should be_true
    converter.__test_arena_fits_def?(foreign_arena, recovered).should be_true

    selected = converter.__test_resolve_arena_for_def(recovered, foreign_arena)
    selected.same?(owner_arena).should be_true
    recovered_arena_body_literal(selected, recovered).should eq(65_i64)
    canonical = converter.__test_canonical_arena_for_def(recovered, foreign_arena)
    canonical.same?(owner_arena).should be_true
    recovered_arena_body_literal(canonical, recovered).should eq(65_i64)
  end

  it "rejects a known shared-body owner that cannot contain the recovered span" do
    owner_source = recovered_arena_source("65")
    foreign_source = owner_source + (" " * 32)
    owner_arena, owner_roots = parse_recovered_arena_source(owner_source)
    foreign_arena, foreign_roots = parse_recovered_arena_source(foreign_source)
    owner_def = recovered_arena_definition(owner_arena, owner_roots)
    recovered_arena_definition(foreign_arena, foreign_roots)

    contradictory_span = Adamas::Compiler::Frontend::Span.new(
      owner_def.span.start_offset, foreign_source.bytesize.to_i32,
      owner_def.span.start_line, owner_def.span.start_column,
      owner_def.span.end_line, owner_def.span.end_column,
    )
    recovered_view = Adamas::Compiler::Frontend::DefNode.new(
      contradictory_span, owner_def.name, owner_def.params, owner_def.return_type, owner_def.body,
      owner_def.is_abstract, owner_def.visibility, owner_def.receiver, owner_def.forall_type_params,
    )

    converter = Adamas::HIR::AstToHir.new(
      foreign_arena,
      sources_by_arena: {
        owner_arena.object_id.to_u64 => owner_source,
        foreign_arena.object_id.to_u64 => foreign_source,
      },
      main_arenas: [foreign_arena, owner_arena],
    )
    converter.__test_register_exact_source_owner("recoverable", owner_def, owner_arena)
    recovered_view.body.not_nil!.same?(owner_def.body.not_nil!).should be_true
    converter.__test_arena_fits_def?(owner_arena, recovered_view).should be_false
    converter.__test_arena_fits_def?(foreign_arena, recovered_view).should be_true

    expect_raises(Adamas::HIR::LoweringError, /registered source body owner does not fit definition/) do
      converter.__test_resolve_arena_for_def(recovered_view, foreign_arena)
    end
  end

  it "rechecks exact body ownership before returning an earlier cached fallback" do
    owner_source = recovered_arena_source("65")
    foreign_source = recovered_arena_source("66")
    owner_arena, owner_roots = parse_recovered_arena_source(owner_source)
    foreign_arena, foreign_roots = parse_recovered_arena_source(foreign_source)
    owner_def = recovered_arena_definition(owner_arena, owner_roots)
    foreign_def = recovered_arena_definition(foreign_arena, foreign_roots)
    owner_def.params.not_nil!.clear
    converter = Adamas::HIR::AstToHir.new(
      foreign_arena,
      sources_by_arena: {
        owner_arena.object_id.to_u64 => owner_source,
        foreign_arena.object_id.to_u64 => foreign_source,
      },
      main_arenas: [foreign_arena, owner_arena],
    )
    recovered = converter.__test_recover_source_def(owner_def, owner_arena).not_nil!

    # Cache a structurally valid caller fallback before the exact source
    # registration is published. Both arenas are already known candidates, so
    # adding the source registration does not incidentally clear this cache.
    converter.__test_resolve_arena_for_def(recovered, foreign_arena).same?(foreign_arena).should be_true
    converter.__test_canonical_arena_for_def(recovered, foreign_arena).same?(foreign_arena).should be_true
    converter.__test_register_exact_source_owner("recoverable", owner_def, owner_arena)

    selected = converter.__test_resolve_arena_for_def(recovered, foreign_arena)
    selected.same?(owner_arena).should be_true
    canonical = converter.__test_canonical_arena_for_def(recovered, foreign_arena)
    canonical.same?(owner_arena).should be_true
    recovered_arena_body_literal(selected, recovered).should eq(65_i64)
    recovered_arena_body_literal(canonical, recovered).should eq(65_i64)
  end
end
