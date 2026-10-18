require "spec"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def test_reparse_macro_argument(id, source, target)
    reparse_expr_for_macro(id, source, target)
  end

  def test_record_generated_argument(arena, id, text)
    macro_generated_sources_for(arena)[id.index] = text
  end

  def test_bind_parsed_source(arena, text)
    set_source_for_arena(arena, text)
  end
end

private def boundary_parse(text, arena = Adamas::Compiler::Frontend::AstArena.new)
  Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(text), arena
  ).parse_program
end

private def boundary_number(arena, id)
  String.new(arena[id].as(Adamas::Compiler::Frontend::NumberNode).value)
end

describe "cross-arena macro argument source ownership" do
  it "transfers an original parser node from its registered buffer" do
    parsed = boundary_parse("123")
    lowerer = Adamas::HIR::AstToHir.new(parsed.arena,
      sources_by_arena: {parsed.arena.object_id.to_u64 => "123"})
    target = Adamas::Compiler::Frontend::AstArena.new
    copied = lowerer.test_reparse_macro_argument(parsed.roots.first, parsed.arena, target)
    boundary_number(target, copied).should eq("123")
  end

  it "rejects an appended node without proof of its source even if offsets and kinds match" do
    parsed = boundary_parse("123")
    lowerer = Adamas::HIR::AstToHir.new(parsed.arena,
      sources_by_arena: {parsed.arena.object_id.to_u64 => "123"})
    appended = boundary_parse("987", parsed.arena)
    target = Adamas::Compiler::Frontend::AstArena.new
    copied = lowerer.test_reparse_macro_argument(appended.roots.first, parsed.arena, target)
    copied.invalid?.should be_true
  end

  it "uses an exact generated source for a same-kind overlapping span" do
    parsed = boundary_parse("123")
    lowerer = Adamas::HIR::AstToHir.new(parsed.arena,
      sources_by_arena: {parsed.arena.object_id.to_u64 => "123"})
    appended = boundary_parse("987", parsed.arena)
    id = appended.roots.first
    lowerer.test_record_generated_argument(parsed.arena, id, "987")
    target = Adamas::Compiler::Frontend::AstArena.new
    copied = lowerer.test_reparse_macro_argument(id, parsed.arena, target)
    boundary_number(target, copied).should eq("987")
  end

  it "certifies a newly completed transient parser arena when its source is bound" do
    main = boundary_parse("123")
    lowerer = Adamas::HIR::AstToHir.new(main.arena,
      sources_by_arena: {main.arena.object_id.to_u64 => "123"})
    transient = boundary_parse("456")
    lowerer.test_bind_parsed_source(transient.arena, "456")
    target = Adamas::Compiler::Frontend::AstArena.new
    copied = lowerer.test_reparse_macro_argument(transient.roots.first, transient.arena, target)
    boundary_number(target, copied).should eq("456")
  end

  it "rejects an original node after the same arena is rebound to a different source" do
    parsed = boundary_parse("123")
    lowerer = Adamas::HIR::AstToHir.new(parsed.arena,
      sources_by_arena: {parsed.arena.object_id.to_u64 => "123"})
    lowerer.test_bind_parsed_source(parsed.arena, "987")
    target = Adamas::Compiler::Frontend::AstArena.new
    copied = lowerer.test_reparse_macro_argument(parsed.roots.first, parsed.arena, target)
    copied.invalid?.should be_true
  end

  it "preserves source ownership for descendants after a second cross-arena transfer" do
    parsed = boundary_parse("{123, {456, 789}}")
    lowerer = Adamas::HIR::AstToHir.new(parsed.arena,
      sources_by_arena: {parsed.arena.object_id.to_u64 => "{123, {456, 789}}"})
    middle = Adamas::Compiler::Frontend::AstArena.new
    copied = lowerer.test_reparse_macro_argument(parsed.roots.first, parsed.arena, middle)
    outer = middle[copied].as(Adamas::Compiler::Frontend::TupleLiteralNode)
    inner = middle[outer.elements[1]].as(Adamas::Compiler::Frontend::TupleLiteralNode)
    target = Adamas::Compiler::Frontend::AstArena.new
    final = lowerer.test_reparse_macro_argument(inner.elements[1], middle, target)
    boundary_number(target, final).should eq("789")
  end
end
