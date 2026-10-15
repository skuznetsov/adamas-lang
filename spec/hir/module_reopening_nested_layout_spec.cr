require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_nested_reopening_layout_fixture
  source = <<-CRYSTAL
    module Linkable
      class SmallNode
        include Linkable
      end
      class PaddedNode
        @padding : Int64
        def initialize(@padding : Int64)
        end
        include Linkable
      end
    end
    module Linkable
      property previous : Linkable?
      property next : Linkable?
    end
    class LinkHolder
      getter node : Linkable
      def initialize(@node : Linkable)
      end
    end
    def link(node : Linkable, previous : Linkable?)
      node.next = node.previous = previous
    end
    small = LinkHolder.new(Linkable::SmallNode.new)
    padded = LinkHolder.new(Linkable::PaddedNode.new(42_i64))
    link(small.node, padded.node)
    CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena,
    sources_by_arena: {arena.object_id.to_u64 => source})
  program.roots.each do |id|
    case node = arena[id]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.pre_register_module_scoped_macros(node)
    end
  end
  main = [] of UInt64
  program.roots.each do |id|
    case node = arena[id]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
    else
      main << id.index.to_u64
    end
  end
  converter.lower_main(main)
  converter.flush_pending_functions
  converter
end

describe "module reopening before nested class layout" do
  it "retains late module fields in both nested concrete layouts" do
    converter = lower_nested_reopening_layout_fixture
    {"Linkable::SmallNode", "Linkable::PaddedNode"}.each do |owner|
      info = converter.class_info[owner]
      info.ivars.map(&.name).should contain("@previous")
      info.ivars.map(&.name).should contain("@next")
      info.ivars.find { |ivar| ivar.name == "@previous" }.not_nil!.type.should_not eq(Adamas::HIR::TypeRef::VOID)
    end
  end

  it "materializes late module accessor targets for nested includers" do
    converter = lower_nested_reopening_layout_fixture
    {"Linkable::SmallNode", "Linkable::PaddedNode"}.each do |owner|
      {"previous=", "next="}.each do |method|
        converter.module.functions.any? { |function| function.name.starts_with?("#{owner}##{method}") && !function.blocks.empty? }.should be_true
      end
    end
  end
end
