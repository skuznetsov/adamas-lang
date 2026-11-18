require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_infer_overload_body_result(
    selected : Adamas::Compiler::Frontend::DefNode,
    selected_arena : Adamas::Compiler::Frontend::ArenaLike,
    sibling : Adamas::Compiler::Frontend::DefNode,
    sibling_arena : Adamas::Compiler::Frontend::ArenaLike,
    explicit_arena : Bool,
  ) : String?
    @function_defs["Owner#probe$Int32"] = selected
    set_function_def_arena("Owner#probe$Int32", selected_arena)
    @function_defs["Owner#probe"] = sibling
    set_function_def_arena("Owner#probe", sibling_arena)
    arena_fits_def?(sibling_arena, selected).should be_true
    with_arena(sibling_arena) do
      infer_concrete_return_type_from_body(selected, "Owner", explicit_arena ? selected_arena : nil)
        .try { |type| get_type_name_from_ref(type) }
    end
  end

  def __test_infer_local_from_unregistered_body(
    body : Array(Adamas::Compiler::Frontend::ExprId),
    owner_arena : Adamas::Compiler::Frontend::ArenaLike,
    ambient_arena : Adamas::Compiler::Frontend::ArenaLike,
    name : String,
  ) : String?
    old_body = @infer_body_context
    @infer_body_context = inference_body_context(body, owner_arena)
    with_arena(ambient_arena) do
      infer_local_type_from_body(body, name, nil).try { |type| get_type_name_from_ref(type) }
    end
  ensure
    @infer_body_context = old_body
  end

  def __test_infer_local_without_owner(
    body : Array(Adamas::Compiler::Frontend::ExprId),
    ambient_arena : Adamas::Compiler::Frontend::ArenaLike,
    name : String,
  ) : String?
    old_body = @infer_body_context
    @infer_body_context = nil
    with_arena(ambient_arena) do
      infer_local_type_from_body(body, name, nil).try { |type| get_type_name_from_ref(type) }
    end
  ensure
    @infer_body_context = old_body
  end

  def __test_infer_local_with_conflicting_owner(
    body : Array(Adamas::Compiler::Frontend::ExprId),
    owner_arena : Adamas::Compiler::Frontend::ArenaLike,
    preferred_arena : Adamas::Compiler::Frontend::ArenaLike,
    name : String,
  ) : String?
    old_body = @infer_body_context
    @infer_body_context = inference_body_context(body, owner_arena)
    infer_local_type_from_body(body, name, nil, preferred_arena).try { |type| get_type_name_from_ref(type) }
  ensure
    @infer_body_context = old_body
  end

  def __test_infer_local_from_prefix(
    body : Array(Adamas::Compiler::Frontend::ExprId),
    owner_arena : Adamas::Compiler::Frontend::ArenaLike,
    ambient_arena : Adamas::Compiler::Frontend::ArenaLike,
    name : String,
  ) : String?
    prefix = body[0...body.size]
    prefix.should_not be(body)
    with_arena(ambient_arena) do
      infer_local_type_from_body(prefix, name, nil, owner_arena).try { |type| get_type_name_from_ref(type) }
    end
  end
end

private def parse_body_arena_owner(source : String)
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  parsed = parser.parse_program
  parser.diagnostics.should be_empty
  {parsed.ast_arena, parsed.roots}
end

describe "speculative local inference source arena ownership" do
  it "uses the selected definition when a family alias fits the same indices and spans" do
    selected_arena, selected_roots = parse_body_arena_owner("def probe(n : Int32)\n  1_i32\nend")
    sibling_arena, sibling_roots = parse_body_arena_owner("def probe(n : Int64)\n  1_i64\nend")
    selected = selected_arena[selected_roots.first].as(Adamas::Compiler::Frontend::DefNode)
    sibling = sibling_arena[sibling_roots.first].as(Adamas::Compiler::Frontend::DefNode)
    selected.span.should eq(sibling.span)
    selected.body.not_nil!.map(&.index).should eq(sibling.body.not_nil!.map(&.index))
    [true, false].each do |explicit_arena|
      converter = Adamas::HIR::AstToHir.new(selected_arena)
      converter.no_prelude = true
      converter.__test_infer_overload_body_result(selected, selected_arena, sibling, sibling_arena, explicit_arena).should eq("Int32")
    end
  end

  it "uses the body's exact owner when a different active arena has colliding ExprIds" do
    owner_arena, owner_body = parse_body_arena_owner("local_value = \"owner\"\n")
    ambient_arena, ambient_body = parse_body_arena_owner("local_value = 17\n")

    owner_body.map(&.index).should eq(ambient_body.map(&.index))
    owner_arena.size.should eq(ambient_arena.size)

    converter = Adamas::HIR::AstToHir.new(owner_arena)
    converter.no_prelude = true
    converter.__test_infer_local_from_unregistered_body(owner_body, owner_arena, ambient_arena, "local_value").should eq("String")
  end

  it "fails closed when the body's source arena is missing" do
    owner_arena, owner_body = parse_body_arena_owner("local_value = \"owner\"\n")
    ambient_arena, _ = parse_body_arena_owner("local_value = 17\n")
    converter = Adamas::HIR::AstToHir.new(owner_arena)
    converter.no_prelude = true

    expect_raises(Adamas::HIR::LoweringError, /cannot establish exact source arena/) do
      converter.__test_infer_local_without_owner(owner_body, ambient_arena, "local_value")
    end
  end

  it "rejects a preferred arena that conflicts with the body's exact owner" do
    owner_arena, owner_body = parse_body_arena_owner("local_value = \"owner\"\n")
    ambient_arena, _ = parse_body_arena_owner("local_value = 17\n")
    converter = Adamas::HIR::AstToHir.new(owner_arena)
    converter.no_prelude = true

    expect_raises(Adamas::HIR::LoweringError, /conflicting source arena/) do
      converter.__test_infer_local_with_conflicting_owner(owner_body, owner_arena, ambient_arena, "local_value")
    end
  end

  it "keeps the proven arena while following assignments inside a nested body" do
    owner_arena, owner_body = parse_body_arena_owner(<<-CR)
      [1].each do
        local_value = "owner"
        alias_value = local_value
      end
      CR
    ambient_arena, ambient_body = parse_body_arena_owner(<<-CR)
      [1].each do
        local_value = 17
        alias_value = local_value
      end
      CR

    owner_body.map(&.index).should eq(ambient_body.map(&.index))
    owner_arena.size.should eq(ambient_arena.size)

    converter = Adamas::HIR::AstToHir.new(owner_arena)
    converter.no_prelude = true
    converter.__test_infer_local_from_unregistered_body(owner_body, owner_arena, ambient_arena, "alias_value").should eq("String")
  end

  it "keeps the proven arena for a prefix array with colliding ExprIds" do
    owner_arena, owner_body = parse_body_arena_owner("local_value = \"owner\"\nalias_value = local_value\n")
    ambient_arena, ambient_body = parse_body_arena_owner("local_value = 17\nalias_value = local_value\n")

    owner_body.map(&.index).should eq(ambient_body.map(&.index))
    owner_arena.size.should eq(ambient_arena.size)

    converter = Adamas::HIR::AstToHir.new(owner_arena)
    converter.no_prelude = true
    converter.__test_infer_local_from_prefix(owner_body, owner_arena, ambient_arena, "alias_value").should eq("String")
  end
end
