require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_constructor_receipt_source_names(
    expected_definition : Adamas::Compiler::Frontend::DefNode,
    expected_arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Array(String)
    names = [] of String
    @function_defs.each do |name, definition|
      next unless definition.same?(expected_definition)
      arena = @function_def_arenas[name]?
      next unless arena && arena.object_id == expected_arena.object_id
      names << name
    end
    names
  end

  def __test_constructor_receipt_binding_matches?(
    name : String,
    expected_definition : Adamas::Compiler::Frontend::DefNode,
    expected_arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Bool
    definition = @function_defs[name]?
    arena = @function_def_arenas[name]?
    definition.try(&.same?(expected_definition)) == true &&
      arena.try { |entry| entry.object_id == expected_arena.object_id } == true
  end

  def __test_constructor_receipt_completed_body?(name : String) : Bool
    @module.has_function_with_body?(name) && function_state(name).completed?
  end
end

private def lower_constructor_initializer_receipt_fixture
  source = <<-CRYSTAL
    class PositionalProcConstructorReceipt
      def initialize(callback : Proc(Int32))
        callback.call
      end

      def self.new(callback) : Int32
        69_i32
      end
    end

    PositionalProcConstructorReceipt.new(-> { 73_i32 })
  CRYSTAL

  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  class_node = program.roots.compact_map do |root_id|
    arena[root_id].as?(Adamas::Compiler::Frontend::ClassNode)
  end.first? || raise "constructor receipt fixture has no class"
  members = class_node.body.not_nil!.compact_map do |member_id|
    arena[member_id].as?(Adamas::Compiler::Frontend::DefNode)
  end
  initializer = members.find { |definition| String.new(definition.name) == "initialize" } ||
                raise "constructor receipt fixture has no initializer"
  explicit_new = members.find do |definition|
    String.new(definition.name) == "new" && definition.has_receiver?
  end || raise "constructor receipt fixture has no explicit class new"

  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
  )
  converter.no_prelude = true
  converter.arena = arena
  main = [] of UInt64
  program.roots.each do |root_id|
    case arena[root_id]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(class_node)
      converter.lower_class(class_node)
    else
      main << root_id.index.to_u64
    end
  end
  converter.lower_main(main)
  converter.flush_pending_functions
  converter.refresh_void_type_params
  converter.flush_deferred_allocators
  {converter, initializer, explicit_new, arena}
end

describe "complete positional constructor initializer receipt" do
  it "keeps the exact initializer source body behind the instance-returning allocator" do
    converter, initializer, explicit_new, arena = lower_constructor_initializer_receipt_fixture
    owner = "PositionalProcConstructorReceipt"
    class_type = converter.class_info[owner].type_ref

    main = converter.module.function_by_name("__adamas_main")
    main.should_not be_nil
    constructor_calls = main.not_nil!.blocks.flat_map(&.instructions)
      .compact_map(&.as?(Adamas::HIR::Call))
      .select { |call| call.method_name.starts_with?("#{owner}.") }
    constructor_calls.size.should eq(1)
    constructor_call = constructor_calls.first
    constructor_call.method_name.should contain(".__adamas_allocator_new")
    constructor_call.type.should eq(class_type)

    allocator_name = constructor_call.method_name
    allocator = converter.module.function_by_name(allocator_name)
    allocator.should_not be_nil
    allocator.not_nil!.return_type.should eq(class_type)
    converter.__test_constructor_receipt_completed_body?(allocator_name).should be_true

    initialize_prefix = "#{owner}#initialize"
    initialize_call = allocator.not_nil!.blocks.flat_map(&.instructions)
      .compact_map(&.as?(Adamas::HIR::Call))
      .find { |call| call.method_name.starts_with?(initialize_prefix) }
    initialize_call.should_not be_nil
    initializer_name = initialize_call.not_nil!.method_name
    converter.__test_constructor_receipt_source_names(initializer, arena).should contain(initializer_name)
    converter.__test_constructor_receipt_binding_matches?(initializer_name, initializer, arena).should be_true

    initializer_body = converter.module.function_by_name(initializer_name)
    initializer_body.should_not be_nil
    converter.__test_constructor_receipt_completed_body?(initializer_name).should be_true

    explicit_names = converter.__test_constructor_receipt_source_names(explicit_new, arena)
    explicit_names.should_not be_empty
    explicit_names.includes?(constructor_call.method_name).should be_false
    explicit_names.each do |name|
      if explicit_body = converter.module.function_by_name(name)
        explicit_body.return_type.should eq(Adamas::HIR::TypeRef::INT32)
      end
    end
  end
end
