require "../spec_helper"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/mir/hir_to_mir"
require "../../src/compiler/mir/optimizations"
require "../../src/compiler/mir/llvm_backend"

private UNION_STATIC_GENERIC_SOURCE = File.read(
  File.expand_path("../../regression_tests/union_static_generic_materialization_guard.cr", __DIR__)
)

private UNION_ARRAY     = "Array(AstArena | PageArena | VirtualArena)"
private UNION_VALUE     = "AstArena | PageArena | VirtualArena"
private APPEND_STATIC   = "append_static$Array(AstArena | PageArena | VirtualArena)_AstArena"
private APPEND_EXPLICIT = "append_explicit$Array(AstArena | PageArena | VirtualArena)_AstArena"
private APPEND_UNION    = "append_union$Array(AstArena | PageArena | VirtualArena)_AstArena | PageArena | VirtualArena"
private SHL_STATIC      = "Array(AstArena | PageArena | VirtualArena)#<<$AstArena"
private SHL_UNION       = "Array(AstArena | PageArena | VirtualArena)#<<$AstArena | PageArena | VirtualArena"
private PUSH_STATIC     = "Array(AstArena | PageArena | VirtualArena)#push$AstArena"
private PUSH_UNION      = "Array(AstArena | PageArena | VirtualArena)#push$AstArena | PageArena | VirtualArena"

private def lower_union_static_generic_source : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(UNION_STATIC_GENERIC_SOURCE)
  )
  program = parser.parse_program
  raise "parser diagnostics: #{parser.diagnostics.size}" unless parser.diagnostics.empty?

  arena = program.arena
  aliases = [] of Adamas::Compiler::Frontend::AliasNode
  classes = [] of Adamas::Compiler::Frontend::ClassNode
  definitions = [] of Adamas::Compiler::Frontend::DefNode
  main_exprs = [] of UInt64

  program.roots.each do |expr_id|
    case node = arena[expr_id]
    when Adamas::Compiler::Frontend::AliasNode
      aliases << node
    when Adamas::Compiler::Frontend::ClassNode
      classes << node
    when Adamas::Compiler::Frontend::DefNode
      definitions << node
    else
      main_exprs << expr_id.index.to_u64
    end
  end

  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => UNION_STATIC_GENERIC_SOURCE}
  )
  aliases.each { |node| converter.register_alias(node) }
  classes.each { |node| converter.register_class(node) }
  definitions.each { |node| converter.register_function(node) }
  classes.each { |node| converter.lower_class(node) }
  definitions.each { |node| converter.lower_def(node) }
  converter.lower_main(main_exprs)
  converter.flush_pending_functions
  converter
end

private def union_static_mir_function(
  mir_module : Adamas::MIR::Module,
  name : String,
) : Adamas::MIR::Function
  matches = mir_module.functions.select { |function| function.name == name }
  matches.size.should eq(1), "missing/duplicate #{name}; available=#{mir_module.functions.map(&.name)}"
  matches.first
end

private def union_static_mir_value_type(
  function : Adamas::MIR::Function,
  value_id : Adamas::MIR::ValueId,
) : Adamas::MIR::TypeRef
  if parameter = function.params.find { |candidate| candidate.index == value_id }
    return parameter.type
  end

  value = function.blocks.flat_map(&.instructions).find { |candidate| candidate.id == value_id }
  value.should_not be_nil
  value.not_nil!.type
end

private def assert_union_static_mir_edge(
  mir_module : Adamas::MIR::Module,
  owner_name : String,
  target_name : String,
) : Adamas::MIR::Call
  owner = union_static_mir_function(mir_module, owner_name)
  target = union_static_mir_function(mir_module, target_name)
  calls = owner.blocks.flat_map(&.instructions).compact_map do |instruction|
    instruction.as?(Adamas::MIR::Call)
  end

  calls.size.should eq(1)
  call = calls.first
  call.callee.should eq(target.id)
  call.args.size.should eq(2)
  call.args[0].should eq(owner.params[0].index)
  union_static_mir_value_type(owner, call.args[0]).should eq(target.params[0].type)
  union_static_mir_value_type(owner, call.args[1]).should eq(target.params[1].type)
  call.type.should eq(target.return_type)
  call
end

private def union_static_llvm_function(output : String, symbol : String) : String
  String.build do |io|
    inside = false
    output.each_line do |line|
      unless inside
        next unless line.starts_with?("define ptr @#{symbol}(")
        inside = true
      end
      io << line << '\n'
      break if line == "}"
    end
  end
end

describe "union-static generic materialization ABI" do
  it "preserves typed FunctionIds and emitted receiver/value calls" do
    converter = lower_union_static_generic_source
    lowering = Adamas::MIR::HIRToMIRLowering.new(converter.module)
    lowering.register_union_types(converter.union_descriptor_entries)
    lowering.register_class_types(converter.class_info)
    mir_module = lowering.lower

    array_type = mir_module.type_registry.get_by_name(UNION_ARRAY).not_nil!
    ast_type = mir_module.type_registry.get_by_name("AstArena").not_nil!
    union_type = mir_module.type_registry.get_by_name(UNION_VALUE).not_nil!

    expected_signatures = {
      APPEND_STATIC   => [array_type.id, ast_type.id, array_type.id],
      APPEND_EXPLICIT => [array_type.id, ast_type.id, array_type.id],
      APPEND_UNION    => [array_type.id, union_type.id, array_type.id],
      SHL_STATIC      => [array_type.id, ast_type.id, array_type.id],
      SHL_UNION       => [array_type.id, union_type.id, array_type.id],
      PUSH_STATIC     => [array_type.id, ast_type.id, array_type.id],
      PUSH_UNION      => [array_type.id, union_type.id, array_type.id],
    }
    expected_signatures.each do |name, signature|
      function = union_static_mir_function(mir_module, name)
      function.params.map(&.type.id).should eq(signature[0, 2])
      function.return_type.id.should eq(signature[2])
    end

    assert_union_static_mir_edge(mir_module, APPEND_STATIC, SHL_STATIC).args.should eq([0_u32, 1_u32])
    explicit_owner = union_static_mir_function(mir_module, APPEND_EXPLICIT)
    explicit_call = assert_union_static_mir_edge(mir_module, APPEND_EXPLICIT, SHL_UNION)
    explicit_call.args[1].should_not eq(explicit_owner.params[1].index)
    explicit_wrap = explicit_owner.blocks.flat_map(&.instructions).find do |instruction|
      instruction.id == explicit_call.args[1]
    end.try(&.as?(Adamas::MIR::UnionWrap))
    explicit_wrap.should_not be_nil
    explicit_wrap.not_nil!.value.should eq(explicit_owner.params[1].index)
    explicit_wrap.not_nil!.type.id.should eq(union_type.id)
    explicit_wrap.not_nil!.union_type.id.should eq(union_type.id)
    assert_union_static_mir_edge(mir_module, APPEND_UNION, SHL_UNION).args.should eq([0_u32, 1_u32])
    assert_union_static_mir_edge(mir_module, SHL_STATIC, PUSH_STATIC).args.should eq([0_u32, 1_u32])
    assert_union_static_mir_edge(mir_module, SHL_UNION, PUSH_UNION).args.should eq([0_u32, 1_u32])

    [PUSH_STATIC, PUSH_UNION].each do |name|
      function = union_static_mir_function(mir_module, name)
      terminator = function.get_block(function.entry_block).terminator.as?(Adamas::MIR::Return)
      terminator.should_not be_nil
      terminator.not_nil!.value.should eq(function.params[0].index)
    end

    generator = Adamas::MIR::LLVMIRGenerator.new(mir_module)
    generator.emit_type_metadata = false
    output = generator.generate
    mapper = Adamas::MIR::LLVMTypeMapper.new(mir_module.type_registry)

    [{SHL_STATIC, PUSH_STATIC}, {SHL_UNION, PUSH_UNION}].each do |pair|
      shl_symbol = mapper.mangle_name(pair[0])
      push_symbol = mapper.mangle_name(pair[1])
      shl_definition = "define ptr @#{shl_symbol}(ptr %self, ptr %value) {"
      push_definition = "define ptr @#{push_symbol}(ptr %self, ptr %value) {"
      output.lines.count { |line| line == shl_definition }.should eq(1)
      output.lines.count { |line| line.starts_with?("define ptr @#{shl_symbol}(") }.should eq(1)
      output.lines.count { |line| line == push_definition }.should eq(1)
      output.lines.count { |line| line.starts_with?("define ptr @#{push_symbol}(") }.should eq(1)

      shl_body = union_static_llvm_function(output, shl_symbol)
      push_body = union_static_llvm_function(output, push_symbol)
      shl_body.lines.count do |line|
        line.includes?("call ptr @#{push_symbol}(ptr %self, ptr %value)")
      end.should eq(1)
      shl_body.lines.count { |line| line.strip.starts_with?("ret ptr ") }.should eq(1)
      push_body.lines.count { |line| line.strip.starts_with?("ret ptr ") }.should eq(1)
      push_body.lines.count { |line| line.strip == "ret ptr %self" }.should eq(1)
      push_body.should_not contain("ret ptr null")
      output.should_not contain("call ptr @#{push_symbol}()")
    end
  end
end
