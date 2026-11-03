require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_observe_captured_yield_target(
    ctx : Adamas::HIR::LoweringContext,
    locals : Hash(String, Adamas::HIR::ValueId),
  ) : {Adamas::HIR::ValueId, Adamas::HIR::TypeRef, Adamas::HIR::ProcCarrier}?
    capture = find_enclosing_yield_target(ctx, locals)
    return nil unless capture
    {capture.target.value_id, capture.target.type, capture.target.carrier}
  end
end

private def capture_producer_converter : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(""))
  arena = parser.parse_program.arena
  Adamas::HIR::AstToHir.new(arena)
end

private def capture_producer_proc_type(converter : Adamas::HIR::AstToHir) : Adamas::HIR::TypeRef
  converter.module.intern_type(Adamas::HIR::TypeDescriptor.new(
    Adamas::HIR::TypeKind::Proc,
    "Proc(Int32)",
    [Adamas::HIR::TypeRef::INT32],
  ))
end

describe "captured yield producer observation" do
  it "materializes a Proc-typed callback when the actual block ABI is raw" do
    converter = capture_producer_converter
    proc_type = capture_producer_proc_type(converter)
    function = converter.module.create_function("CaptureProducerRawProc#owner", Adamas::HIR::TypeRef::VOID)
    block = function.add_param("callback", proc_type, true)
    context = Adamas::HIR::LoweringContext.new(function, converter.module, converter.arena)
    context.register_type(block.id, proc_type)

    target = converter.__test_observe_captured_yield_target(context, {"callback" => block.id}).not_nil!
    target[1].should eq(proc_type)
    target[2].should eq(Adamas::HIR::ProcCarrier::HeapProcObject)
    context.value_for(target[0]).should be_a(Adamas::HIR::MakeProc)
  end

  it "uses a raw FuncPointer producer even when the enclosing block ABI is heap" do
    converter = capture_producer_converter
    proc_type = capture_producer_proc_type(converter)
    function = converter.module.create_function("CaptureProducerHeapFlagRawValue#owner", Adamas::HIR::TypeRef::VOID)
    function.heap_block_param = true
    block = function.add_param("callback", proc_type, true)
    context = Adamas::HIR::LoweringContext.new(function, converter.module, converter.arena)
    context.register_type(block.id, proc_type)
    raw_proc = Adamas::HIR::FuncPointer.new(context.next_id, proc_type, "CaptureProducerRawValue#callback")
    context.emit(raw_proc)
    context.register_type(raw_proc.id, proc_type)

    target = converter.__test_observe_captured_yield_target(context, {"callback" => raw_proc.id}).not_nil!
    target[1].should eq(proc_type)
    target[2].should eq(Adamas::HIR::ProcCarrier::HeapProcObject)
    context.value_for(target[0]).should be_a(Adamas::HIR::MakeProc)
  end

  it "preserves a raw Pointer callback" do
    converter = capture_producer_converter
    function = converter.module.create_function("CaptureProducerRawPointer#owner", Adamas::HIR::TypeRef::VOID)
    block = function.add_param("callback", Adamas::HIR::TypeRef::POINTER, true)
    context = Adamas::HIR::LoweringContext.new(function, converter.module, converter.arena)
    context.register_type(block.id, Adamas::HIR::TypeRef::POINTER)

    target = converter.__test_observe_captured_yield_target(context, {"callback" => block.id}).not_nil!
    target.should eq({block.id, Adamas::HIR::TypeRef::POINTER, Adamas::HIR::ProcCarrier::RawFnptrCallback})
    function.blocks.flat_map(&.instructions).should be_empty
  end

  it "keeps an already-heap Proc parameter without rematerializing it" do
    converter = capture_producer_converter
    proc_type = capture_producer_proc_type(converter)
    function = converter.module.create_function("CaptureProducerHeapProc#owner", Adamas::HIR::TypeRef::VOID)
    function.heap_block_param = true
    block = function.add_param("callback", proc_type, true)
    context = Adamas::HIR::LoweringContext.new(function, converter.module, converter.arena)
    context.register_type(block.id, proc_type)

    target = converter.__test_observe_captured_yield_target(context, {"callback" => block.id}).not_nil!
    target.should eq({block.id, proc_type, Adamas::HIR::ProcCarrier::HeapProcObject})
    function.blocks.flat_map(&.instructions).should be_empty
  end
end
