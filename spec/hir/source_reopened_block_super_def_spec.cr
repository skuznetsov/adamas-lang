require "../spec_helper"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_reopened_block_super_target(
    module_name : String,
    method_name : String,
    positional_count : Int32 = 0,
    named_names : Array(String) = [] of String,
  ) : Tuple(Adamas::Compiler::Frontend::DefNode, Adamas::Compiler::Frontend::ArenaLike, String)?
    find_module_block_super_def(
      module_name,
      method_name,
      positional_count,
      named_names,
      Set(String).new,
    )
  end
end

private def reopened_block_super_converter(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "/tmp/source_reopened_block_super_def.cr"},
  )
  converter.no_prelude = true
  program.roots.each do |root_id|
    if node = arena[root_id].as?(Adamas::Compiler::Frontend::ModuleNode)
      converter.register_module(node)
    end
  end
  converter
end

describe "reopened module block-super target" do
  it "selects the latest compatible Def and retains its source arena" do
    source = <<-CRYSTAL
      module ReopenedBlockSuperBase
        def marker(& : Int32 -> Int32) : Int32
          yield 65
        end
      end
      module ReopenedBlockSuperBase
        def marker(& : Int32 -> Int32) : Int32
          yield 66
        end
      end
    CRYSTAL
    converter = reopened_block_super_converter(source)

    selected = converter.__test_reopened_block_super_target(
      "ReopenedBlockSuperBase",
      "marker",
    ).not_nil!
    selected[0].span.start_line.should eq(7)
    selected[1].object_id.should eq(converter.arena.object_id)
    selected[2].should eq("ReopenedBlockSuperBase")
  end

  it "skips a newer overload that does not accept the supplied block shape" do
    source = <<-CRYSTAL
      module ReopenedBlockSuperShape
        def marker(& : Int32 -> Int32) : Int32
          yield 65
        end
      end
      module ReopenedBlockSuperShape
        def marker(value : Int32) : Int32
          value
        end
      end
    CRYSTAL
    converter = reopened_block_super_converter(source)

    selected = converter.__test_reopened_block_super_target(
      "ReopenedBlockSuperShape",
      "marker",
      0,
    ).not_nil!
    selected[0].span.start_line.should eq(2)
    selected[2].should eq("ReopenedBlockSuperShape")
  end
end
