require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_virtual_module_argument_specialization(include_descriptor_only_call : Bool = false) : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    module VirtualDescriptor
    end

    class VirtualIO
    end

    class VirtualFD < VirtualIO
      include VirtualDescriptor
    end

    class VirtualSocket < VirtualIO
      include VirtualDescriptor
    end

    class VirtualNotIO
      include VirtualDescriptor
    end

    module VirtualLoop
      abstract def read(io : VirtualDescriptor) : Int32
    end

    class VirtualPoller
      include VirtualLoop

      def read(io : VirtualDescriptor) : Int32
        check_open(io)
      end

      def check_open(io : VirtualIO) : Int32
        65
      end
    end

    class VirtualInheritedPoller < VirtualPoller
    end

    def selected : VirtualLoop
      VirtualPoller.new
    end

    def selected_inherited : VirtualLoop
      VirtualInheritedPoller.new
    end

    selected.read(VirtualFD.new)
    selected.read(VirtualSocket.new)
    selected_inherited.read(VirtualFD.new)
    selected_inherited.read(VirtualSocket.new)
  CRYSTAL
  if include_descriptor_only_call
    source += "\nselected.read(VirtualNotIO.new)\n"
  end

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
  converter.arena = arena
  converter.no_prelude = true

  main = [] of UInt64
  program.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
    else
      main << root_id.index.to_u64
    end
  end

  converter.lower_main(main)
  converter.flush_pending_functions
  converter.refresh_void_type_params
  converter.flush_deferred_allocators
  converter
end

describe "virtual module argument specialization" do
  it "materializes the concrete argument bodies for direct and inherited implementations" do
    converter = lower_virtual_module_argument_specialization
    main = converter.module.function_by_name("__adamas_main")
    main.should_not be_nil
    read_calls = main.not_nil!.blocks.flat_map(&.instructions)
      .compact_map(&.as?(Adamas::HIR::Call))
      .select { |call| call.method_name.includes?("#read") }
    read_calls.size.should eq(4)
    read_calls.all?(&.virtual).should be_true

    {"VirtualFD", "VirtualSocket"}.each do |argument_name|
      function_name = "VirtualPoller#read$#{argument_name}"
      converter.module.has_function_with_body?(function_name).should be_true
      function = converter.module.function_by_name(function_name).not_nil!
      function.params.size.should eq(2)
      function.params[1].type.should eq(converter.class_info[argument_name].type_ref)

      instructions = function.blocks.flat_map(&.instructions)
      inner_calls = instructions
        .compact_map(&.as?(Adamas::HIR::Call))
        .select { |call| call.method_name.starts_with?("VirtualPoller#check_open$") }
      inner_calls.should_not be_empty
      inner_calls.all? do |call|
        next false unless call.args.size == 1

        argument_id = call.args.first
        if argument_id == function.params[1].id
          true
        else
          argument_value = instructions.find { |instruction| instruction.id == argument_id }
          if copy = argument_value.try(&.as?(Adamas::HIR::Copy))
            copy.type == function.params[1].type && copy.source == function.params[1].id
          else
            false
          end
        end
      end.should be_true
    end

    converter.module.has_function_with_body?("VirtualPoller#read$VirtualDescriptor").should be_false
    converter.module.class_parents["VirtualInheritedPoller"].should eq("VirtualPoller")
  end

  it "keeps the implementation's narrower inner restriction" do
    expect_raises(Adamas::HIR::LoweringError, /check_open/) do
      lower_virtual_module_argument_specialization(include_descriptor_only_call: true)
    end
  end
end
