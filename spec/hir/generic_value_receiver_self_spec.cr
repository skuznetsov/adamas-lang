require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_generic_value_receiver_fixture(name : String) : Adamas::HIR::Module
  source = File.read(File.join(
    __DIR__, "../../regression_tests/fixtures/generic_value_receiver_self", name,
  ))
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty

  converter = Adamas::HIR::AstToHir.new(
    program.arena,
    sources_by_arena: {program.arena.object_id.to_u64 => source},
  )
  converter.no_prelude = true
  main = [] of UInt64
  program.roots.each do |id|
    case node = program.arena[id]
    when Adamas::Compiler::Frontend::LibNode
      converter.register_lib(node)
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
  converter.module
end

private def expect_generic_receiver_contract(
  mod : Adamas::HIR::Module,
  type : Adamas::HIR::TypeRef,
) : Nil
  main = mod.function_by_name("__adamas_main").not_nil!
  main_literals = main.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Literal))
  main_literals.any? { |literal| literal.type == type && literal.int_value == 65_i64 }.should be_true

  # Dispatch is inlined. Check the typed callback inputs in their owning
  # functions instead of requiring a retained dispatch Call or named body.
  callback_types = [] of Adamas::HIR::TypeRef
  mod.functions.each do |function|
    instructions = function.blocks.flat_map(&.instructions)
    instructions.compact_map(&.as?(Adamas::HIR::Yield)).each do |yielded|
      yielded.args.each do |argument_id|
        argument = instructions.find { |instruction| instruction.id == argument_id }
        argument.should_not be_nil
        callback_types << argument.not_nil!.type
      end
    end
  end
  callback_types.should_not be_empty
  callback_types.all? { |argument_type| argument_type == type }.should be_true
end

describe "numeric generic value receivers" do
  it "lowers an Int32 type parameter value as an Int32 instance receiver" do
    mod = lower_generic_value_receiver_fixture("int32_receiver.cr")
    expect_generic_receiver_contract(mod, Adamas::HIR::TypeRef::INT32)
  end

  it "preserves an Int64 type parameter value width at instance dispatch" do
    mod = lower_generic_value_receiver_fixture("int64_receiver.cr")
    expect_generic_receiver_contract(mod, Adamas::HIR::TypeRef::INT64)
  end

  it "keeps a type parameter bound to Int32 on the class-method receiver path" do
    mod = lower_generic_value_receiver_fixture("type_parameter_class_receiver.cr")
    main = mod.function_by_name("__adamas_main").not_nil!
    main_calls = main.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::ExternCall))
    main_calls.count { |call| call.extern_name == "putchar" }.should eq(2)
  end

  it "rejects an Int64 generic receiver when its callback requires Int32" do
    expect_raises(Adamas::HIR::LoweringError) do
      lower_generic_value_receiver_fixture("int64_receiver_int32_block.cr")
    end
  end

  it "keeps direct numeric literal instance dispatch as a control" do
    mod = lower_generic_value_receiver_fixture("direct_literal_receiver.cr")
    main = mod.function_by_name("__adamas_main").not_nil!
    main_calls = main.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::ExternCall))
    main_calls.count { |call| call.extern_name == "putchar" }.should eq(2)
  end
end
