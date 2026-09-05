require "spec"
require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_multiple_assign_type_name(type_ref : Adamas::HIR::TypeRef) : String
    get_type_name_from_ref(type_ref)
  end
end

private def nullable_tuple_parse(
  source : String,
) : {Adamas::Compiler::Frontend::ArenaLike, Array(Adamas::Compiler::Frontend::ExprId)}
  result = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  ).parse_program
  {result.arena, result.roots}
end

private def lower_nullable_tuple_program(
  source : String,
  function_name : String,
) : {Adamas::HIR::AstToHir, Adamas::HIR::Function}
  arena, roots = nullable_tuple_parse(source)
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
  )
  converter.arena = arena

  class_nodes = [] of Adamas::Compiler::Frontend::ClassNode
  def_nodes = [] of Adamas::Compiler::Frontend::DefNode
  roots.each do |root_id|
    case root = arena[root_id]
    when Adamas::Compiler::Frontend::ClassNode
      class_nodes << root
    when Adamas::Compiler::Frontend::DefNode
      def_nodes << root
    end
  end

  class_nodes.each { |node| converter.register_class(node) }
  def_nodes.each { |node| converter.register_function(node) }
  class_nodes.each { |node| converter.lower_class(node) }

  target = def_nodes.find { |node| String.new(node.name) == function_name }
  raise "function #{function_name} not found" unless target
  {converter, converter.lower_def(target)}
end

private def nullable_tuple_index_gets(
  converter : Adamas::HIR::AstToHir,
  function : Adamas::HIR::Function,
) : Array(Adamas::HIR::IndexGet)
  functions = converter.module.functions.select do |candidate|
    candidate == function || candidate.name.starts_with?("__crystal_proc_") ||
      candidate.name.starts_with?("__crystal_block_proc_")
  end
  functions.flat_map do |candidate|
    candidate.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::IndexGet))
  end
end

describe "nullable tuple multiple assignment lowering" do
  it "keeps each captured destructured position's HIR type" do
    converter, function = lower_nullable_tuple_program(<<-CRYSTAL, "probe")
      class Node
      end

      class Arena
      end

      class OtherArena
      end

      def probe(resolved : Tuple(String, Node, Arena | OtherArena)?)
        reader = -> do
          if resolved
            name, node, arena = resolved
            node
          else
            nil
          end
        end
        reader.call
      end
    CRYSTAL

    index_gets = nullable_tuple_index_gets(converter, function)
    index_gets.size.should eq(3)
    index_gets.map { |index_get| converter.__test_multiple_assign_type_name(index_get.type) }.should eq([
      "String",
      "Node",
      "Arena | OtherArena",
    ])
    index_gets.none? { |index_get| index_get.type == Adamas::HIR::TypeRef::VOID }.should be_true
  end

  it "keeps unions of multiple concrete tuples positionally merged" do
    converter, function = lower_nullable_tuple_program(<<-CRYSTAL, "probe")
      class Node
      end

      def probe(resolved : Tuple(String, Node) | Tuple(Int32, Node) | Nil)
        reader = -> do
          if resolved
            first, node = resolved
            node
          else
            nil
          end
        end
        reader.call
      end
    CRYSTAL

    index_gets = nullable_tuple_index_gets(converter, function)
    index_gets.size.should eq(2)
    index_gets.map { |index_get| converter.__test_multiple_assign_type_name(index_get.type) }.should eq([
      "Int32 | String",
      "Node",
    ])
  end
end
