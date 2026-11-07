require "../spec_helper"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_canonical_source_method_key(
    base_name : String,
    node : Adamas::Compiler::Frontend::DefNode,
    arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : String
    with_arena(arena) { canonical_function_name_for_def(base_name, node) }
  end

  def __test_register_source_type_method(
    owner : String,
    node : Adamas::Compiler::Frontend::DefNode,
    arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Nil
    with_arena(arena) do
      register_type_method_from_def(node, owner, known_arena: arena)
    end
  end

  def __test_register_source_module_method(
    owner : String,
    node : Adamas::Compiler::Frontend::DefNode,
    arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Nil
    with_arena(arena) do
      register_module_method_from_def(node, owner)
    end
  end

  def __test_source_method_binding(
    name : String,
  ) : NamedTuple(
    definition: Adamas::Compiler::Frontend::DefNode?,
    arena: Adamas::Compiler::Frontend::ArenaLike?,
    return_type: TypeRef?,
  )
    {
      definition: @function_defs[name]?,
      arena:       @function_def_arenas[name]?,
      return_type: @function_types[name]?,
    }
  end
end

private def parse_source_method_key_program(source : String)
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source)
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty
  program
end

private def source_method_key_defs(program, method_name : String) : Array(Adamas::Compiler::Frontend::DefNode)
  program.roots.compact_map do |expr_id|
    program.arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode)
  end.select do |node|
    String.new(node.name) == method_name
  end
end

private def source_module_method_def(
  program,
  module_name : String,
  method_name : String,
) : Adamas::Compiler::Frontend::DefNode
  module_node = program.roots.compact_map do |expr_id|
    program.arena[expr_id].as?(Adamas::Compiler::Frontend::ModuleNode)
  end.find { |node| String.new(node.name) == module_name }
  raise "module #{module_name} not found" unless module_node

  body = module_node.body || raise "module body not found"
  body.compact_map do |expr_id|
    program.arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode)
  end.find { |node| String.new(node.name) == method_name } || raise "method #{method_name} not found"
end

describe "source method declaration keys" do
  it "keeps canonical keys stable when the exact source definition occupies the registry" do
    source = <<-CRYSTAL
      def key_zero
        65
      end

      def key_untyped(value)
        value
      end

      def key_partial(value : String, fallback = 65)
        value
      end

      def key_restricted(value : Int32)
        value
      end

      def key_named(*, label : Int32)
        label
      end

      def key_block(&block : Int32 -> Int32)
        yield 65
      end

      def key_splat(*items : Int32)
        items
      end

      def key_double_splat(**items : Int32)
        items
      end
    CRYSTAL
    program = parse_source_method_key_program(source)
    arena = program.arena

    [
      {"key_zero", "KeyReplayZero"},
      {"key_untyped", "KeyReplayUntyped"},
      {"key_partial", "KeyReplayPartial"},
      {"key_restricted", "KeyReplayRestricted"},
      {"key_named", "KeyReplayNamed"},
      {"key_block", "KeyReplayBlock"},
      {"key_splat", "KeyReplaySplat"},
      {"key_double_splat", "KeyReplayDoubleSplat"},
    ].each do |method_name, owner|
      node = source_method_key_defs(program, method_name).first
      node.should_not be_nil
      node = node.not_nil!
      base_name = "#{owner}##{method_name}"
      converter = Adamas::HIR::AstToHir.new(arena)
      converter.no_prelude = true

      unoccupied_key = converter.__test_canonical_source_method_key(base_name, node, arena)
      converter.__test_register_source_type_method(owner, node, arena)
      occupied_key = converter.__test_canonical_source_method_key(base_name, node, arena)

      occupied_key.should eq(unoccupied_key), "#{method_name} changed key after its source Def/Arena was registered"
      binding = converter.__test_source_method_binding(unoccupied_key)
      binding[:definition].try(&.same?(node)).should be_true
      binding[:arena].try(&.same?(arena)).should be_true

      # Replaying the same physical source pair must remain idempotent.
      converter.__test_register_source_type_method(owner, node, arena)
      replayed = converter.__test_source_method_binding(unoccupied_key)
      replayed[:definition].try(&.same?(node)).should be_true
      replayed[:arena].try(&.same?(arena)).should be_true
    end
  end

  it "keeps overload identity in the source signature rather than registry order" do
    program = parse_source_method_key_program(<<-CRYSTAL)
      def arity_shape
        65
      end

      def arity_shape(value)
        value
      end

      def restriction_shape(value : Int32)
        value
      end

      def restriction_shape(value : String)
        value
      end

      def partial_shape(value : Int32, fallback = 65)
        value
      end

      def partial_shape(value : String, fallback = "x")
        value
      end

      def label_shape(*, left : Int32)
        left
      end

      def label_shape(*, right : Int32)
        right
      end

      def block_shape
        65
      end

      def block_shape(&block : Int32 -> Int32)
        yield 65
      end

      def splat_shape(value : Int32)
        value
      end

      def splat_shape(*values : Int32)
        values
      end

      def double_splat_shape(value : Int32)
        value
      end

      def double_splat_shape(**values : Int32)
        values
      end
    CRYSTAL
    arena = program.arena
    converter = Adamas::HIR::AstToHir.new(arena)

    key = ->(name : String, index : Int32) do
      node = source_method_key_defs(program, name)[index]
      converter.__test_canonical_source_method_key("KeyShape##{name}", node, arena)
    end

    key.call("arity_shape", 0).should_not eq(key.call("arity_shape", 1))
    key.call("restriction_shape", 0).should_not eq(key.call("restriction_shape", 1))
    key.call("partial_shape", 0).should_not eq(key.call("partial_shape", 1))
    key.call("label_shape", 0).should_not eq(key.call("label_shape", 1))
    key.call("block_shape", 0).should_not eq(key.call("block_shape", 1))
    key.call("splat_shape", 0).should_not eq(key.call("splat_shape", 1))
    key.call("double_splat_shape", 0).should_not eq(key.call("double_splat_shape", 1))
  end

  it "publishes the final module Def, arena, and return type after same-key registration and replay" do
    first_source = <<-CRYSTAL
      module StableModuleMethodOwner
        def result : Int32
          65
        end
      end
    CRYSTAL
    second_source = <<-CRYSTAL
      module StableModuleMethodOwner
        def result : Int64
          4294967296_i64
        end
      end
    CRYSTAL
    first_program = parse_source_method_key_program(first_source)
    second_program = parse_source_method_key_program(second_source)
    first_arena = first_program.arena
    second_arena = second_program.arena
    first_def = source_module_method_def(first_program, "StableModuleMethodOwner", "result")
    second_def = source_module_method_def(second_program, "StableModuleMethodOwner", "result")
    binding_name = "StableModuleMethodOwner#result"
    converter = Adamas::HIR::AstToHir.new(
      first_arena,
      sources_by_arena: {
        first_arena.object_id.to_u64  => first_source,
        second_arena.object_id.to_u64 => second_source,
      },
    )
    converter.no_prelude = true

    converter.__test_register_source_module_method("StableModuleMethodOwner", first_def, first_arena)
    first_binding = converter.__test_source_method_binding(binding_name)
    first_binding[:definition].try(&.same?(first_def)).should be_true
    first_binding[:arena].try(&.same?(first_arena)).should be_true
    first_binding[:return_type].should eq(Adamas::HIR::TypeRef::INT32)

    converter.__test_register_source_module_method("StableModuleMethodOwner", second_def, second_arena)
    replacement = converter.__test_source_method_binding(binding_name)
    replacement[:definition].try(&.same?(second_def)).should be_true
    replacement[:arena].try(&.same?(second_arena)).should be_true
    replacement[:return_type].should eq(Adamas::HIR::TypeRef::INT64)

    converter.__test_register_source_module_method("StableModuleMethodOwner", second_def, second_arena)
    replayed = converter.__test_source_method_binding(binding_name)
    replayed[:definition].try(&.same?(second_def)).should be_true
    replayed[:arena].try(&.same?(second_arena)).should be_true
    replayed[:return_type].should eq(Adamas::HIR::TypeRef::INT64)
  end
end
