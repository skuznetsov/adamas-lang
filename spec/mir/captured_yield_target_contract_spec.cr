require "../spec_helper"
require "../../src/compiler/hir/hir"
require "../../src/compiler/mir/mir"
require "../../src/compiler/mir/hir_to_mir"

# A load from a closure box retains a Proc signature, but that signature is
# shared by raw callbacks and heap Proc objects. The selected yield contract
# carries the representation independently of its capture storage.
private def captured_yield_contract_case(
  carrier : Adamas::HIR::ProcCarrier,
  direct_raw_producer : Bool = false,
  mismatch_type : Bool = false,
) : {Adamas::MIR::HIRToMIRLowering, String}
  hir = Adamas::HIR::Module.new("captured_yield_contract")
  proc_type = hir.intern_type(Adamas::HIR::TypeDescriptor.new(
    Adamas::HIR::TypeKind::Proc,
    "Proc(Int32, Int32)",
    [Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::INT32]
  ))
  func = hir.create_function("captured_callback", Adamas::HIR::TypeRef::INT32)
  env = func.add_param("environment", Adamas::HIR::TypeRef::POINTER)
  argument = func.add_param("value", Adamas::HIR::TypeRef::INT32)
  body = func.get_block(func.entry_block)
  target = if direct_raw_producer
             raw = Adamas::HIR::FuncPointer.new(func.next_value_id, proc_type, "captured_callback")
             body.add(raw)
             raw.id
           else
             slot = Adamas::HIR::FieldGet.new(func.next_value_id, Adamas::HIR::TypeRef::POINTER,
               env.id, "callback_box", 0)
             body.add(slot)
             load = Adamas::HIR::PointerLoad.new(func.next_value_id, proc_type, slot.id)
             body.add(load)
             load.id
           end
  declared_type = mismatch_type ? Adamas::HIR::TypeRef::POINTER : proc_type
  contract = Adamas::HIR::YieldTarget.new(target, declared_type, carrier)
  yielded = Adamas::HIR::Yield.new(func.next_value_id, Adamas::HIR::TypeRef::INT32,
    [argument.id], target, contract)
  body.add(yielded)
  body.terminator = Adamas::HIR::Return.new(yielded.id)
  {Adamas::MIR::HIRToMIRLowering.new(hir), func.name}
end

private def captured_yield_calls(lowering : Adamas::MIR::HIRToMIRLowering, name : String)
  lowering.mir_module.functions.find { |func| func.name == name }.not_nil!
    .blocks.flat_map(&.instructions)
    .select(Adamas::MIR::IndirectCall)
end

describe "captured yield target contract" do
  it "keeps the heap Proc environment after a capture-box load" do
    lowering, name = captured_yield_contract_case(Adamas::HIR::ProcCarrier::HeapProcObject)
    lowering.lower
    captured_yield_calls(lowering, name).map(&.args.size).sort.should eq([1, 2])
  end

  it "keeps an equally typed raw callback raw across the same box load" do
    lowering, name = captured_yield_contract_case(Adamas::HIR::ProcCarrier::RawFnptrCallback)
    lowering.lower
    captured_yield_calls(lowering, name).map(&.args.size).should eq([1])
  end

  it "rejects a contract contradicting an exact raw producer before an indirect call" do
    lowering, name = captured_yield_contract_case(Adamas::HIR::ProcCarrier::HeapProcObject,
      direct_raw_producer: true)
    expect_raises(Exception, /yield target carrier contradicts its producer/) { lowering.lower }
    captured_yield_calls(lowering, name).should be_empty
  end

  it "rejects a stale signature before an indirect call" do
    lowering, name = captured_yield_contract_case(Adamas::HIR::ProcCarrier::HeapProcObject,
      mismatch_type: true)
    expect_raises(Exception, /yield target contract lost its selected signature/) { lowering.lower }
    captured_yield_calls(lowering, name).should be_empty
  end

  it "rejects a contract attached to another SSA binding" do
    contract = Adamas::HIR::YieldTarget.new(3_u32, Adamas::HIR::TypeRef::POINTER,
      Adamas::HIR::ProcCarrier::RawFnptrCallback)
    expect_raises(ArgumentError, /exact binding/) do
      Adamas::HIR::Yield.new(4_u32, Adamas::HIR::TypeRef::NIL, [] of UInt32, 2_u32, contract)
    end
  end
end
