require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_initializer_default_binding_fixture(source : String) : Adamas::HIR::AstToHir
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
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
    else
      main << root.index.to_u64
    end
  end
  program.roots.each do |root|
    case node = arena[root]
    when Adamas::Compiler::Frontend::ClassNode
      converter.lower_class(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.lower_def(node)
    end
  end
  converter.lower_main(main)
  converter.flush_pending_functions
  converter.refresh_void_type_params
  converter.flush_deferred_allocators
  converter
end

private def initializer_default_binding_allocators(converter : Adamas::HIR::AstToHir) : Array(Adamas::HIR::Function)
  converter.module.functions.select do |function|
    function.name.starts_with?("DefaultOwner.") && !function.blocks.empty? &&
      function.blocks.flat_map(&.instructions).any? do |instruction|
        instruction.as?(Adamas::HIR::Call).try(&.method_name.includes?("DefaultOwner#initialize"))
      end
  end
end

describe "selected initializer defaults in generated allocators" do
  it "passes an omitted object constant to the selected initialize source body" do
    converter = lower_initializer_default_binding_fixture(<<-CRYSTAL)
      struct DefaultValue
        @value : Int32

        def initialize(@value : Int32)
        end

        def value : Int32
          @value
        end
      end

      class DefaultOwner
        DEFAULT = DefaultValue.new(65)

        def initialize(@every = DEFAULT)
        end

        def every
          @every
        end
      end

      DefaultOwner.new.every.value
      CRYSTAL

    allocators = initializer_default_binding_allocators(converter)
    allocators.should_not be_empty
    allocator = allocators.find do |function|
      function.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call)).any? do |call|
        call.method_name.includes?("DefaultOwner#initialize") && call.args.size == 1 &&
          function.blocks.flat_map(&.instructions).any? do |instruction|
            instruction.id == call.args[0] && instruction.is_a?(Adamas::HIR::ClassVarGet)
          end
      end
    end
    allocator.should_not be_nil

    instructions = allocator.not_nil!.blocks.flat_map(&.instructions)
    init_call = instructions.compact_map(&.as?(Adamas::HIR::Call)).find do |call|
      call.method_name.includes?("DefaultOwner#initialize")
    end
    init_call.should_not be_nil
    init_call.not_nil!.args.size.should eq(1)

    default_value = instructions.find { |instruction| instruction.id == init_call.not_nil!.args[0] }
    default_value.should be_a(Adamas::HIR::ClassVarGet)
    default_get = default_value.as(Adamas::HIR::ClassVarGet)
    default_get.class_name.should eq("DefaultOwner")
    default_get.var_name.should eq("DEFAULT")
    default_get.type.should eq(converter.class_info["DefaultValue"].type_ref)
  end

  it "keeps a supplied initializer argument as the call value" do
    converter = lower_initializer_default_binding_fixture(<<-CRYSTAL)
      struct DefaultValue
        @value : Int32

        def initialize(@value : Int32)
        end
      end

      class DefaultOwner
        DEFAULT = DefaultValue.new(65)

        def initialize(@every = DEFAULT)
        end
      end

      DefaultOwner.new(DefaultValue.new(66))
      CRYSTAL

    allocators = initializer_default_binding_allocators(converter)
    allocator = allocators.find do |function|
      function.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call)).any? do |call|
        call.method_name.includes?("DefaultOwner#initialize") && call.args.size == 1
      end
    end
    allocator.should_not be_nil

    instructions = allocator.not_nil!.blocks.flat_map(&.instructions)
    init_call = instructions.compact_map(&.as?(Adamas::HIR::Call)).find do |call|
      call.method_name.includes?("DefaultOwner#initialize")
    end
    init_call.should_not be_nil
    init_call.not_nil!.args.size.should eq(1)
    actual = allocator.not_nil!.params.find { |param| param.id == init_call.not_nil!.args[0] }
    actual.should_not be_nil
    actual.not_nil!.type.should eq(converter.class_info["DefaultValue"].type_ref)
  end
end
