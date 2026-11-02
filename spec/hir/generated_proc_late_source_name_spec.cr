require "../spec_helper"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/hir/ast_to_hir"

private def lower_late_macro_proc_name_source(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source)
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty

  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
  )
  converter.no_prelude = true

  macro_nodes = [] of Adamas::Compiler::Frontend::MacroDefNode
  def_nodes = [] of Adamas::Compiler::Frontend::DefNode
  main_exprs = [] of UInt64
  program.roots.each do |expr_id|
    case node = arena[expr_id]
    when Adamas::Compiler::Frontend::MacroDefNode
      macro_nodes << node
    when Adamas::Compiler::Frontend::DefNode
      def_nodes << node
    else
      main_exprs << expr_id.index.to_u64
    end
  end

  # Match the CLI phases: macros and source signatures are registered before
  # main lowering; executable roots retain source order within main.
  macro_nodes.each do |node|
    converter.arena = arena
    converter.register_macro(node)
  end
  def_nodes.each do |node|
    converter.arena = arena
    converter.register_function(node)
  end

  converter.lower_main(main_exprs)
  converter.flush_pending_functions
  converter
end

private def returned_integer(function : Adamas::HIR::Function) : Int64?
  values = function.blocks.flat_map(&.instructions).compact
  function.blocks.each do |block|
    return_id = block.terminator.as?(Adamas::HIR::Return).try(&.value)
    next unless return_id
    return values.find { |value| value.id == return_id }
      .try(&.as?(Adamas::HIR::Literal))
      .try(&.int_value)
  end
  nil
end

describe "late macro source Proc name publication" do
  it "keeps the macro-published source body and selected call distinct from an earlier Proc literal" do
    converter = lower_late_macro_proc_name_source(<<-CRYSTAL)
      callback = -> { 1 }

      macro publish_proc_name
        def __crystal_proc_0 : Int32
          2
        end
      end

      publish_proc_name
      __crystal_proc_0
    CRYSTAL

    source_function = converter.module.function_by_name("__crystal_proc_0")
    source_function.should_not be_nil
    source_function = source_function.not_nil!
    source_function.return_type.should eq(Adamas::HIR::TypeRef::INT32)
    returned_integer(source_function).should eq(2_i64)

    main = converter.module.function_by_name("__adamas_main")
    main.should_not be_nil
    selected_call = main.not_nil!.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
      .find { |call| call.method_name == source_function.name }
    selected_call.should_not be_nil
    selected_call.not_nil!.method_name.should eq(source_function.name)
  end

  it "keeps a macro-published block Proc spelling distinct from an earlier block body" do
    converter = lower_late_macro_proc_name_source(<<-CRYSTAL)
      def invoke(&block : -> Int32) : Int32
        block.call
      end

      callback = invoke { 1 }

      macro publish_block_proc_name
        def __crystal_block_proc_0 : Int32
          2
        end
      end

      publish_block_proc_name
      __crystal_block_proc_0
    CRYSTAL

    source_function = converter.module.function_by_name("__crystal_block_proc_0")
    source_function.should_not be_nil
    source_function = source_function.not_nil!
    source_function.return_type.should eq(Adamas::HIR::TypeRef::INT32)
    returned_integer(source_function).should eq(2_i64)

    generated_block = converter.module.functions.find do |function|
      function.name.starts_with?("__crystal_block_proc_0") && function.name.includes?("\x01")
    end
    generated_block.should_not be_nil
    generated_block.not_nil!.should_not be(source_function)

    main = converter.module.function_by_name("__adamas_main")
    main.should_not be_nil
    selected_call = main.not_nil!.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
      .find { |call| call.method_name == source_function.name }
    selected_call.should_not be_nil
    selected_call.not_nil!.method_name.should eq(source_function.name)
  end
end
