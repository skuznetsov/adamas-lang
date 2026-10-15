require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_module_setter_fixture(assignment : String)
  source = <<-CRYSTAL
    module Linkable
      property previous : Linkable?
      property next : Linkable?
    end
    class SmallNode
      include Linkable
    end
    class PaddedNode
      @padding : Int64
      def initialize(@padding : Int64)
      end
      include Linkable
    end
    class LinkHolder
      getter node : Linkable
      def initialize(@node : Linkable)
      end
    end
    def link(node : Linkable, previous : Linkable?)
      #{assignment}
    end
    small = LinkHolder.new(SmallNode.new)
    padded = LinkHolder.new(PaddedNode.new(42_i64))
    link(small.node, padded.node)
    CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena,
    sources_by_arena: {arena.object_id.to_u64 => source})
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

describe "module-typed setter dispatch" do
  {"direct" => "node.previous = previous", "chained" => "node.next = node.previous = previous"}.each do |label, assignment|
    it "materializes concrete targets and emits virtual calls for #{label} assignment" do
      converter = lower_module_setter_fixture(assignment)
      calls = converter.module.functions.flat_map(&.blocks).flat_map(&.instructions)
        .compact_map(&.as?(Adamas::HIR::Call)).select { |call| call.method_name.starts_with?("Linkable#") && call.method_name.includes?("=") }
      calls.should_not be_empty
      calls.all?(&.virtual).should be_true
      {"SmallNode", "PaddedNode"}.each do |owner|
        converter.module.functions.any? { |function| function.name.starts_with?("#{owner}#previous=") && !function.blocks.empty? }.should be_true
      end
    end
  end
end
