require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_explicit_indexer_probe(code : String) : Adamas::HIR::Function
  lexer = Adamas::Compiler::Frontend::Lexer.new(code)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  program = parser.parse_program
  raise "parser diagnostics: #{parser.diagnostics.size}" unless parser.diagnostics.empty?

  arena = program.arena
  class_nodes = [] of Adamas::Compiler::Frontend::ClassNode
  alias_nodes = [] of Adamas::Compiler::Frontend::AliasNode
  def_nodes = [] of Adamas::Compiler::Frontend::DefNode
  program.roots.each do |expr_id|
    case node = arena[expr_id]
    when Adamas::Compiler::Frontend::ClassNode
      class_nodes << node
    when Adamas::Compiler::Frontend::AliasNode
      alias_nodes << node
    when Adamas::Compiler::Frontend::DefNode
      def_nodes << node
    end
  end

  def_expr = def_nodes.find { |node| String.new(node.name) == "probe" }
  raise "probe definition not found" unless def_expr

  converter = Adamas::HIR::AstToHir.new(arena)
  alias_nodes.each { |node| converter.register_alias(node) }
  class_nodes.each { |node| converter.register_class(node) }
  def_nodes.each { |node| converter.register_function(node) }
  class_nodes.each { |node| converter.lower_class(node) }
  converter.lower_def(def_expr)
end

describe "HIR explicit dotted indexer calls" do
  it "keeps ExprId as the single argument of ArenaLike#[]?" do
    function = lower_explicit_indexer_probe(<<-CRYSTAL)
      class Node
      end

      struct ExprId
      end

      class AstArena
        def []?(id : ExprId) : Node?
          nil
        end
      end

      class VirtualArena
        def []?(id : ExprId) : Node?
          nil
        end
      end

      class PageArena
        def []?(id : ExprId) : Node?
          nil
        end
      end

      alias ArenaLike = AstArena | PageArena | VirtualArena

      def probe(arena : ArenaLike, root_id : ExprId) : Node?
        arena.[]?(root_id)
      end
    CRYSTAL

    calls = function.blocks.flat_map(&.instructions).compact_map do |instruction|
      instruction.as?(Adamas::HIR::Call)
    end

    index_calls = calls.select { |call| call.method_name.includes?("#[]?") }
    index_calls.size.should eq(1)
    index_call = index_calls.first
    index_call.virtual.should be_true
    index_call.args.size.should eq(1)

    # A parser split would produce a zero-arg []? followed by a call on the
    # nullable result. That result-call shape must not survive into HIR.
    calls.none? { |call| call.method_name.includes?("#call") }.should be_true
  end
end
