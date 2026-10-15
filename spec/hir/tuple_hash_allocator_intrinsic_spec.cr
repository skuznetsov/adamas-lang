require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_tuple_hash_allocator_fixture(code : String) : Adamas::HIR::AstToHir
  lexer = Adamas::Compiler::Frontend::Lexer.new(code)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  parsed = parser.parse_program
  arena = parsed.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => code},
    paths_by_arena: {arena.object_id.to_u64 => File.expand_path("src/stdlib/hash_contract_spec.cr")},
    stdlib_root: File.expand_path("src/stdlib"),
  )
  converter.arena = arena

  module_nodes = [] of Adamas::Compiler::Frontend::ModuleNode
  class_nodes = [] of Adamas::Compiler::Frontend::ClassNode
  def_nodes = [] of Adamas::Compiler::Frontend::DefNode
  main_exprs = [] of UInt64

  parsed.roots.each do |expr_id|
    case node = arena[expr_id]
    when Adamas::Compiler::Frontend::ModuleNode
      module_nodes << node
    when Adamas::Compiler::Frontend::ClassNode
      class_nodes << node
    when Adamas::Compiler::Frontend::DefNode
      def_nodes << node
    when Adamas::Compiler::Frontend::CallNode
      main_exprs << expr_id.index.to_u64
    end
  end

  module_nodes.each { |node| converter.register_module(node) }
  class_nodes.each { |node| converter.register_class(node) }
  def_nodes.each { |node| converter.register_function(node) }

  module_nodes.each { |node| converter.lower_module(node) }
  class_nodes.each { |node| converter.lower_class(node) }
  def_nodes.each { |node| converter.lower_def(node) }
  converter.lower_main(main_exprs) unless main_exprs.empty?
  converter.flush_pending_functions
  converter
end

describe "Tuple hash intrinsic allocator materialization" do
  it "materializes the exact full-arity Hasher allocator body" do
    source = <<-CRYSTAL
      module Crystal
        struct Hasher
          def initialize(@a : UInt64, @b : UInt64)
          end

          def result : UInt64
            @a ^ @b
          end
        end
      end

      struct Tuple
        def hash(hasher : Crystal::Hasher) : Crystal::Hasher
          hasher
        end
      end

      def tuple_hash(value : Tuple(String, Int32)) : UInt64
        value.hash
      end

      tuple_hash({"value", 42})
    CRYSTAL
    converter = lower_tuple_hash_allocator_fixture(source)

    allocator_name = "Crystal::Hasher.new$UInt64_UInt64"
    allocator = converter.module.function_by_name(allocator_name)
    allocator.should_not be_nil
    converter.module.has_function_with_body?(allocator_name).should be_true

    caller = converter.module.function_by_name("tuple_hash$Tuple(String, Int32)")
    caller.should_not be_nil
    ctor_calls = caller.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
      instruction.as?(Adamas::HIR::Call)
    end.select { |call| call.method_name.starts_with?("Crystal::Hasher.new") }
    ctor_calls.size.should eq(1)
    ctor_calls.first.method_name.should eq(allocator_name)
    ctor_calls.first.args.size.should eq(2)
  end
end
