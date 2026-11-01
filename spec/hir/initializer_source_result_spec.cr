require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_initializer_source_result_fixture(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty

  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
  )
  converter.no_prelude = true
  converter.arena = arena

  main = [] of UInt64
  program.roots.each do |root|
    case node = arena[root]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
      converter.lower_class(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
    else
      main << root.index.to_u64
    end
  end
  converter.lower_main(main)
  converter.flush_pending_functions
  converter.refresh_void_type_params
  converter.flush_deferred_allocators
  converter
end

private def hir_function_with_body(converter : Adamas::HIR::AstToHir, prefix : String) : Adamas::HIR::Function
  converter.module.functions.find do |function|
    function.name.starts_with?(prefix) && !function.blocks.empty?
  end.not_nil!
end

describe "initializer source result and allocator ABI" do
  it "returns an unannotated initializer value to direct source callers" do
    source = <<-CRYSTAL
      class ResultReader
        @marker : Int32

        def initialize(value : Int32)
          @marker = value
          value
        end

        def direct(value : Int32) : Int32
          initialize(value)
        end
      end

      ResultReader.new(65)
      CRYSTAL
    converter = lower_initializer_source_result_fixture(source)
    initializer = hir_function_with_body(converter, "ResultReader#initialize")
    initializer.return_type.should eq(Adamas::HIR::TypeRef::INT32)
    initializer.blocks.flat_map(&.instructions).any? do |instruction|
      instruction.is_a?(Adamas::HIR::FieldSet) && instruction.field_name.lstrip('@') == "marker"
    end.should be_true

    direct = hir_function_with_body(converter, "ResultReader#direct")
    direct_call = direct.blocks.flat_map(&.instructions)
      .compact_map(&.as?(Adamas::HIR::Call))
      .find { |call| call.method_name.starts_with?("ResultReader#initialize") }
    direct_call.should_not be_nil
    direct_call.not_nil!.type.should eq(Adamas::HIR::TypeRef::INT32)
    direct.return_type.should eq(Adamas::HIR::TypeRef::INT32)
  end

  it "discards the initializer value in new while preserving field initialization" do
    source = <<-CRYSTAL
      class ResultReader
        @marker : Int32

        def initialize(value : Int32)
          @marker = value
          value
        end
      end

      ResultReader.new(65)
      CRYSTAL
    converter = lower_initializer_source_result_fixture(source)
    allocated_type = converter.class_info["ResultReader"].type_ref
    allocators = converter.module.functions.select do |function|
      (function.name == "ResultReader.new" || function.name.starts_with?("ResultReader.new$")) &&
        !function.blocks.empty?
    end
    allocators.should_not be_empty

    allocators.each do |allocator|
      instructions = allocator.blocks.flat_map(&.instructions)
      call_index = instructions.index do |instruction|
        instruction.is_a?(Adamas::HIR::Call) &&
          instruction.method_name.starts_with?("ResultReader#initialize")
      end
      call_index.should_not be_nil
      init_call = instructions[call_index.not_nil!].as(Adamas::HIR::Call)
      init_call.type.should eq(Adamas::HIR::TypeRef::INT32)

      default_store_index = instructions.index do |instruction|
        instruction.is_a?(Adamas::HIR::FieldSet) && instruction.field_name.lstrip('@') == "marker"
      end
      default_store_index.should_not be_nil
      (default_store_index.not_nil! < call_index.not_nil!).should be_true

      allocator.return_type.should eq(allocated_type)
      allocation = instructions.compact_map(&.as?(Adamas::HIR::Allocate)).find do |value|
        value.type == allocated_type
      end
      allocation.should_not be_nil
      allocator.blocks.any? do |block|
        terminator = block.terminator.as?(Adamas::HIR::Return)
        terminator && terminator.value == allocation.not_nil!.id
      end.should be_true
    end
  end

  it "preserves an explicit initializer result annotation for direct calls" do
    source = <<-CRYSTAL
      class AnnotatedReader
        def initialize : String
          "ready"
        end

        def direct : String
          initialize
        end
      end

      AnnotatedReader.new
      CRYSTAL
    converter = lower_initializer_source_result_fixture(source)
    initializer = hir_function_with_body(converter, "AnnotatedReader#initialize")
    initializer.return_type.should eq(Adamas::HIR::TypeRef::STRING)

    direct = hir_function_with_body(converter, "AnnotatedReader#direct")
    direct_call = direct.blocks.flat_map(&.instructions)
      .compact_map(&.as?(Adamas::HIR::Call))
      .find { |call| call.method_name.starts_with?("AnnotatedReader#initialize") }
    direct_call.should_not be_nil
    direct_call.not_nil!.type.should eq(initializer.return_type)
  end

  it "preserves a terminal NoReturn initializer through generated new" do
    source = <<-CRYSTAL
      class TerminalInitializer
        def initialize : NoReturn
          while true
          end
        end
      end

      TerminalInitializer.new
      CRYSTAL
    converter = lower_initializer_source_result_fixture(source)
    allocator = hir_function_with_body(converter, "TerminalInitializer.new")
    init_call = allocator.blocks.flat_map(&.instructions)
      .compact_map(&.as?(Adamas::HIR::Call))
      .find { |call| call.method_name.starts_with?("TerminalInitializer#initialize") }
    init_call.should_not be_nil
    converter.module.get_type_descriptor(init_call.not_nil!.type).not_nil!.name.should eq("NoReturn")
    converter.module.get_type_descriptor(allocator.return_type).not_nil!.name.should eq("NoReturn")
    allocator.blocks.any? { |block| block.terminator.is_a?(Adamas::HIR::Return) }.should be_false
  end
end
