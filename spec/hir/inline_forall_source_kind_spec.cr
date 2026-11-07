require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_inline_block_return_kind_is_explicit?(
    block : Adamas::Compiler::Frontend::BlockNode,
    arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Bool
    inline_block_return_kind_is_explicit?(block, arena)
  end
end

private def inline_forall_block_kind_is_explicit?(expression : String) : Bool
  source = <<-CRYSTAL
    class InlineForallKindProbe
    end
    inline_yielding { #{expression} }
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena,
    sources_by_arena: {arena.object_id.to_u64 => source})
  program.roots.each do |root|
    if node = arena[root].as?(Adamas::Compiler::Frontend::ClassNode)
      converter.register_class(node)
    end
  end
  call = program.roots.compact_map do |root|
    arena[root].as?(Adamas::Compiler::Frontend::CallNode)
  end.last.not_nil!
  block_id = call.block.not_nil!
  block = arena[block_id].as(Adamas::Compiler::Frontend::BlockNode)
  converter.__test_inline_block_return_kind_is_explicit?(block, arena)
end

describe "inline forall callback result source kinds" do
  it "keeps an explicitly named type literal eligible for early binding" do
    inline_forall_block_kind_is_explicit?("InlineForallKindProbe").should be_true
  end

  it "defers a call result whose carrier may erase the value kind" do
    inline_forall_block_kind_is_explicit?("InlineForallKindProbe.make").should be_false
  end

  it "defers a control-flow join whose carrier may mix instance and class values" do
    inline_forall_block_kind_is_explicit?(
      "if flag; InlineForallKindProbe; else; InlineForallKindProbe.new; end",
    ).should be_false
  end

  it "keeps a scalar literal eligible for early binding" do
    inline_forall_block_kind_is_explicit?("41").should be_true
  end
end
