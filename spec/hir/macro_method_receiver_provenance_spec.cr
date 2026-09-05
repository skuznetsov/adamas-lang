require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_macro_receiver_kind(node : Adamas::Compiler::Frontend::DefNode, generated : Bool) : Bool
    mark_macro_generated_parameter_def(node) if generated
    def_receiver_is_self_from_node(node, @arena)
  end
end

private def macro_receiver_kind(parsed_source : String, arena_source : String, generated : Bool) : Bool
  parsed = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(parsed_source)
  ).parse_program
  node = parsed.arena[parsed.roots.first].as(Adamas::Compiler::Frontend::DefNode)
  converter = Adamas::HIR::AstToHir.new(
    parsed.arena,
    sources_by_arena: {parsed.arena.object_id.to_u64 => arena_source},
  )
  converter.__test_macro_receiver_kind(node, generated)
end

describe "macro method receiver provenance" do
  it "keeps an expanded self receiver when its local span overlaps an original instance method" do
    macro_receiver_kind("def self.make; 1; end", "def unrelated; 1; end", true).should be_true
  end

  it "keeps an expanded instance method when its local span overlaps an original class method" do
    macro_receiver_kind("def make; 1; end", "def self.x; 1; end", true).should be_false
  end

  it "retains source-backed receiver recovery for an ordinary definition" do
    macro_receiver_kind("def make; 1; end", "def self.x; 1; end", false).should be_true
  end

  it "retains source-backed instance identity for an ordinary definition" do
    macro_receiver_kind("def self.make; 1; end", "def unrelated; 1; end", false).should be_false
  end
end
