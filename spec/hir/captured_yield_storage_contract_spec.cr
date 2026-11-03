require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_find_captured_yield_target(
    ctx : Adamas::HIR::LoweringContext,
    locals : Hash(String, Adamas::HIR::ValueId),
  ) : {Adamas::HIR::ValueId, Adamas::HIR::TypeRef, Adamas::HIR::ProcCarrier}?
    capture = find_enclosing_yield_target(ctx, locals)
    return nil unless capture
    {capture.target.value_id, capture.target.type, capture.target.carrier}
  end

  def __test_install_captured_yield_target(
    captures : Array({String, Adamas::HIR::ValueId, Adamas::HIR::TypeRef}),
    name : String,
    value_id : Adamas::HIR::ValueId,
    type : Adamas::HIR::TypeRef,
    carrier : Adamas::HIR::ProcCarrier,
  ) : Nil
    install_captured_yield_target(
      captures,
      CapturedYieldTarget.new(name, YieldTarget.new(value_id, type, carrier)),
    )
  end
end

private def lower_captured_yield_storage_source(source : String, inline_depth : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(
    program.arena,
    sources_by_arena: {program.arena.object_id.to_u64 => source},
  )
  converter.no_prelude = true

  previous_disable = ENV["ADAMAS_DISABLE_INLINE_YIELD"]?
  previous_depth = ENV["INLINE_YIELD_MAX_DEPTH"]?
  begin
    ENV.delete("ADAMAS_DISABLE_INLINE_YIELD")
    ENV["INLINE_YIELD_MAX_DEPTH"] = inline_depth
    converter.lower_main(program.roots.map(&.index.to_u64))
    converter.flush_pending_functions
  ensure
    if previous_disable
      ENV["ADAMAS_DISABLE_INLINE_YIELD"] = previous_disable
    else
      ENV.delete("ADAMAS_DISABLE_INLINE_YIELD")
    end
    if previous_depth
      ENV["INLINE_YIELD_MAX_DEPTH"] = previous_depth
    else
      ENV.delete("INLINE_YIELD_MAX_DEPTH")
    end
  end
  converter
end

private def captured_proc_yields(converter : Adamas::HIR::AstToHir) : Array(Tuple(Adamas::HIR::Function, Adamas::HIR::Yield))
  found = [] of Tuple(Adamas::HIR::Function, Adamas::HIR::Yield)
  converter.module.functions.each do |function|
    function.blocks.each do |block|
      block.instructions.each do |instruction|
        next unless yielded = instruction.as?(Adamas::HIR::Yield)
        next unless contract = yielded.target_contract
        next unless converter.module.get_type_descriptor(contract.type).try(&.kind) == Adamas::HIR::TypeKind::Proc
        found << {function, yielded}
      end
    end
  end
  found
end

private def assert_captured_proc_yields_use_heap_storage(converter : Adamas::HIR::AstToHir) : Nil
  yielded = captured_proc_yields(converter)
  yielded.should_not be_empty
  yielded.each do |function, instruction|
    contract = instruction.target_contract.not_nil!
    contract.carrier.should eq(Adamas::HIR::ProcCarrier::HeapProcObject)
    storage_value = function.blocks.flat_map(&.instructions).find { |value| value.id == contract.value_id }
    storage_value.should_not be_nil
    storage_value.not_nil!.type.should eq(contract.type)
    (storage_value.is_a?(Adamas::HIR::ClassVarGet) || storage_value.is_a?(Adamas::HIR::PointerLoad)).should be_true
  end

  same_function_make_proc_storage = converter.module.functions.any? do |function|
    make_proc_ids = function.blocks.flat_map(&.instructions)
      .compact_map(&.as?(Adamas::HIR::MakeProc)).map(&.id)
    stored_values = function.blocks.flat_map(&.instructions).compact_map do |value|
      case value
      when Adamas::HIR::ClassVarSet
        value.value
      when Adamas::HIR::PointerStore
        value.value
      else
        nil
      end
    end
    stored_values.any? { |value_id| make_proc_ids.includes?(value_id) }
  end
  same_function_make_proc_storage.should be_true
end

describe "captured yield storage contract" do
  it "normalizes a raw Proc callback before forming the named capture tuple" do
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(""))
    arena = parser.parse_program.arena
    converter = Adamas::HIR::AstToHir.new(arena)
    proc_type = converter.module.intern_type(Adamas::HIR::TypeDescriptor.new(
      Adamas::HIR::TypeKind::Proc,
      "Proc(Int32)",
      [Adamas::HIR::TypeRef::INT32],
    ))
    function = converter.module.create_function("CapturedYieldRawProc#owner", Adamas::HIR::TypeRef::VOID)
    block = function.add_param("callback", proc_type, true)
    context = Adamas::HIR::LoweringContext.new(function, converter.module, arena)
    context.register_type(block.id, proc_type)

    target = converter.__test_find_captured_yield_target(context, {"callback" => block.id}).not_nil!
    target[1].should eq(proc_type)
    target[2].should eq(Adamas::HIR::ProcCarrier::HeapProcObject)
    context.value_for(target[0]).should be_a(Adamas::HIR::MakeProc)

    captures = [{"callback", block.id, proc_type}]
    converter.__test_install_captured_yield_target(
      captures,
      "callback",
      target[0],
      target[1],
      target[2],
    )
    captures.size.should eq(1)
    captures.first[1].should eq(target[0])
  end

  it "preserves a genuinely raw Pointer callback" do
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(""))
    arena = parser.parse_program.arena
    converter = Adamas::HIR::AstToHir.new(arena)
    function = converter.module.create_function("CapturedYieldRawPointer#owner", Adamas::HIR::TypeRef::VOID)
    block = function.add_param("callback", Adamas::HIR::TypeRef::POINTER, true)
    context = Adamas::HIR::LoweringContext.new(function, converter.module, arena)
    context.register_type(block.id, Adamas::HIR::TypeRef::POINTER)

    target = converter.__test_find_captured_yield_target(context, {"callback" => block.id}).not_nil!
    target.should eq({block.id, Adamas::HIR::TypeRef::POINTER, Adamas::HIR::ProcCarrier::RawFnptrCallback})
    function.blocks.flat_map(&.instructions).should be_empty
  end

  it "keeps an already-heap Proc target without rematerializing it" do
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(""))
    arena = parser.parse_program.arena
    converter = Adamas::HIR::AstToHir.new(arena)
    proc_type = converter.module.intern_type(Adamas::HIR::TypeDescriptor.new(
      Adamas::HIR::TypeKind::Proc,
      "Proc(Int32)",
      [Adamas::HIR::TypeRef::INT32],
    ))
    function = converter.module.create_function("CapturedYieldHeapProc#owner", Adamas::HIR::TypeRef::VOID)
    function.heap_block_param = true
    block = function.add_param("callback", proc_type, true)
    context = Adamas::HIR::LoweringContext.new(function, converter.module, arena)
    context.register_type(block.id, proc_type)

    target = converter.__test_find_captured_yield_target(context, {"callback" => block.id}).not_nil!
    target.should eq({block.id, proc_type, Adamas::HIR::ProcCarrier::HeapProcObject})
    function.blocks.flat_map(&.instructions).should be_empty
  end

  it "rejects a Proc capture whose storage carrier cannot be proved" do
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(""))
    arena = parser.parse_program.arena
    converter = Adamas::HIR::AstToHir.new(arena)
    proc_type = converter.module.intern_type(Adamas::HIR::TypeDescriptor.new(
      Adamas::HIR::TypeKind::Proc,
      "Proc(Int32)",
      [Adamas::HIR::TypeRef::INT32],
    ))
    function = converter.module.create_function("CapturedYieldUnknownProc#owner", Adamas::HIR::TypeRef::VOID)
    block = function.add_param("callback", proc_type, true)
    context = Adamas::HIR::LoweringContext.new(function, converter.module, arena)
    context.register_type(block.id, proc_type)
    unknown = Adamas::HIR::Literal.new(context.next_id, proc_type, nil)
    context.emit(unknown)
    context.register_type(unknown.id, proc_type)

    expect_raises(Exception, "captured Proc callback has no proven heap storage carrier") do
      converter.__test_find_captured_yield_target(context, {"callback" => unknown.id})
    end
  end

  it "boxes the actual raw Proc producer even under a heap block ABI" do
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(""))
    arena = parser.parse_program.arena
    converter = Adamas::HIR::AstToHir.new(arena)
    proc_type = converter.module.intern_type(Adamas::HIR::TypeDescriptor.new(
      Adamas::HIR::TypeKind::Proc,
      "Proc(Int32)",
      [Adamas::HIR::TypeRef::INT32],
    ))
    function = converter.module.create_function("CapturedYieldHeapOwnerRawValue#owner", Adamas::HIR::TypeRef::VOID)
    function.heap_block_param = true
    block = function.add_param("callback", proc_type, true)
    context = Adamas::HIR::LoweringContext.new(function, converter.module, arena)
    context.register_type(block.id, proc_type)
    raw_proc = Adamas::HIR::FuncPointer.new(context.next_id, proc_type, "CapturedYieldRawValue#callback")
    context.emit(raw_proc)
    context.register_type(raw_proc.id, proc_type)

    target = converter.__test_find_captured_yield_target(context, {"callback" => raw_proc.id}).not_nil!
    target[1].should eq(proc_type)
    target[2].should eq(Adamas::HIR::ProcCarrier::HeapProcObject)
    context.value_for(target[0]).should be_a(Adamas::HIR::MakeProc)
  end

  it "carries the materialized target through a nested block Proc capture" do
    converter = lower_captured_yield_storage_source(<<-CRYSTAL, "1")
      def fallback_scope_value(&block : -> Int32) : Int32
        yield
      end

      def fallback_scope_outer(&block : -> Int32) : Int32
        fallback_scope_value { yield }
      end

      fallback_scope_outer { 65 }
    CRYSTAL
    assert_captured_proc_yields_use_heap_storage(converter)
  end
end
