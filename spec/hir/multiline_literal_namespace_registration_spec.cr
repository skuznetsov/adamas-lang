require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_multiline_module_arena_fits?(
    arena : Adamas::Compiler::Frontend::ArenaLike,
    node : Adamas::Compiler::Frontend::ModuleNode,
  ) : Bool
    arena_fits_module_node?(arena, node)
  end

  def __test_multiline_registered_run? : Bool
    @function_defs.has_key?("LiteralPositionHost::Launcher#run")
  end
end

describe "namespace registration after multiline literals" do
  {
    "heredoc"        => "<<-TEXT\n      first\n      second\n      TEXT",
    "percent string" => "%q{first\nsecond\nthird}",
    "percent regex"  => "%r{first\nsecond\nthird}",
  }.each do |kind, literal|
    it "retains the parser-owned class after a #{kind}" do
      source = "module LiteralPositionHost\n  class Launcher\n    def banner\n      #{literal}\n    end\n    def run : Int32\n      42\n    end\n  end\nend\n"
      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program
      arena = parser.arena
      node = program.roots.compact_map { |id| arena[id].as?(Adamas::Compiler::Frontend::ModuleNode) }.first
      converter = Adamas::HIR::AstToHir.new(arena)
      converter.bootstrap_bind_source_maps(
        {arena.object_id.to_u64 => source},
        {arena.object_id.to_u64 => "multiline_namespace.cr"},
      )
      converter.bootstrap_bind_main_arenas([arena] of Adamas::Compiler::Frontend::ArenaLike)
      converter.__test_multiline_module_arena_fits?(arena, node).should be_true
      converter.register_module(node)
      converter.get_class_info("LiteralPositionHost::Launcher").should_not be_nil
      converter.__test_multiline_registered_run?.should be_true
    end
  end
end
