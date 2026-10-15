require "../spec_helper"
require "../../src/compiler/hir/hir"
require "../../src/compiler/mir/mir"
require "../../src/compiler/mir/hir_to_mir"

private struct OnceRawCallbackObservation
  getter call : Adamas::MIR::Call
  getter callback_pointer : Adamas::MIR::FuncPointer
  getter raw_callback_parameter_id : Adamas::HIR::ValueId?
  getter caller : Adamas::MIR::Function
  getter target : Adamas::MIR::Function
  getter type_registry : Adamas::MIR::TypeRegistry

  def initialize(
    @call : Adamas::MIR::Call,
    @callback_pointer : Adamas::MIR::FuncPointer,
    @raw_callback_parameter_id : Adamas::HIR::ValueId?,
    @caller : Adamas::MIR::Function,
    @target : Adamas::MIR::Function,
    @type_registry : Adamas::MIR::TypeRegistry,
  )
  end
end

private def lower_once_raw_callback_case(
  env_value : Int64 = 0_i64,
  copy_proc : Bool = false,
  mismatch_signature : Bool = false,
  mismatch_callback_signature : Bool = false,
  heap_callee : Bool = false,
  yield_to_block : Bool = true,
  copied_raw_pointer_parameter : Bool = false,
  pointer_void_parameter : Bool = false,
  block_param_name : String = "block",
  opaque_block_formal : Bool = false,
  cast_null_env : Bool = false,
) : OnceRawCallbackObservation
  hir_mod = Adamas::HIR::Module.new("once_raw_callback_carrier")
  callback_func = hir_mod.create_function("once_callback", Adamas::HIR::TypeRef::NIL)
  callback_func.add_param("value", Adamas::HIR::TypeRef::INT32) if mismatch_callback_signature
  callback_nil = Adamas::HIR::Literal.new(
    callback_func.next_value_id,
    Adamas::HIR::TypeRef::NIL,
    nil
  )
  callback_func.get_block(callback_func.entry_block).add(callback_nil)
  callback_func.get_block(callback_func.entry_block).terminator = Adamas::HIR::Return.new(callback_nil.id)

  raw_proc_type = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
    Adamas::HIR::TypeKind::Proc,
    "Proc(Nil)",
    [Adamas::HIR::TypeRef::NIL]
  ))
  actual_proc_type = if mismatch_signature
                       hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
                         Adamas::HIR::TypeKind::Proc,
                         "Proc(Int32, Nil)",
                         [Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::NIL]
                       ))
                     else
                       raw_proc_type
                     end

  target = hir_mod.create_function("Crystal::Once.exec$Pointer(Bool)_block", Adamas::HIR::TypeRef::NIL)
  target.heap_block_param = heap_callee
  block_type = if opaque_block_formal
                 Adamas::HIR::TypeRef::POINTER
               else
                 raw_proc_type
               end
  block_param = target.add_param(block_param_name, block_type, true)
  target_body = target.get_block(target.entry_block)
  if yield_to_block && !heap_callee
    yielded = Adamas::HIR::Yield.new(
      target.next_value_id,
      Adamas::HIR::TypeRef::NIL,
      [] of Adamas::HIR::ValueId,
      block_param.id
    )
    target_body.add(yielded)
    target_body.terminator = Adamas::HIR::Return.new(yielded.id)
  else
    nil_value = Adamas::HIR::Literal.new(target.next_value_id, Adamas::HIR::TypeRef::NIL, nil)
    target_body.add(nil_value)
    target_body.terminator = Adamas::HIR::Return.new(nil_value.id)
  end

  caller_hir = hir_mod.create_function("once_raw_callback_caller", Adamas::HIR::TypeRef::NIL)
  caller_body = caller_hir.get_block(caller_hir.entry_block)
  raw_callback_parameter_id = nil.as(Adamas::HIR::ValueId?)
  callback_source_id = nil.as(Adamas::HIR::ValueId?)
  pointer_void_type = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
    Adamas::HIR::TypeKind::Pointer,
    "Pointer(Void)",
    [Adamas::HIR::TypeRef::VOID]
  ))
  if copied_raw_pointer_parameter
    raw_callback_type = pointer_void_parameter ? pointer_void_type : Adamas::HIR::TypeRef::POINTER
    raw_callback_parameter = caller_hir.add_param("callback", raw_callback_type)
    raw_callback_parameter_id = raw_callback_parameter.id
  end
  callback = Adamas::HIR::FuncPointer.new(
    caller_hir.next_value_id,
    Adamas::HIR::TypeRef::POINTER,
    "once_callback"
  )
  caller_body.add(callback)
  callback_source_id = callback.id
  if copied_raw_pointer_parameter
    callback_source = Adamas::HIR::Copy.new(
      caller_hir.next_value_id,
      pointer_void_parameter ? pointer_void_type : Adamas::HIR::TypeRef::POINTER,
      raw_callback_parameter_id.not_nil!
    )
    caller_body.add(callback_source)
    callback_source_id = callback_source.id
  end
  env_id = if cast_null_env
             env_literal = Adamas::HIR::Literal.new(
               caller_hir.next_value_id,
               Adamas::HIR::TypeRef::INT64,
               env_value
             )
             caller_body.add(env_literal)
             env_cast = Adamas::HIR::Cast.new(
               caller_hir.next_value_id,
               Adamas::HIR::TypeRef::POINTER,
               env_literal.id,
               Adamas::HIR::TypeRef::POINTER
             )
             caller_body.add(env_cast)
             env_cast.id
           else
             env_literal = Adamas::HIR::Literal.new(
               caller_hir.next_value_id,
               Adamas::HIR::TypeRef::POINTER,
               env_value
             )
             caller_body.add(env_literal)
             env_literal.id
           end
  proc_value = Adamas::HIR::MakeProc.new(
    caller_hir.next_value_id,
    actual_proc_type,
    callback_source_id.not_nil!,
    env_id
  )
  caller_body.add(proc_value)
  passed_value = proc_value.id
  if copy_proc
    copied = Adamas::HIR::Copy.new(caller_hir.next_value_id, actual_proc_type, proc_value.id)
    caller_body.add(copied)
    passed_value = copied.id
  end
  call = Adamas::HIR::Call.without_receiver(
    caller_hir.next_value_id,
    Adamas::HIR::TypeRef::NIL,
    target.name,
    [passed_value]
  )
  caller_body.add(call)
  caller_body.terminator = Adamas::HIR::Return.new(call.id)

  mir_mod = Adamas::MIR::HIRToMIRLowering.new(hir_mod).lower
  mir_caller = mir_mod.functions.find { |function| function.name == caller_hir.name }.not_nil!
  mir_target = mir_mod.get_function(target.name).not_nil!
  mir_call = mir_caller.blocks
    .flat_map(&.instructions)
    .find { |instruction| instruction.is_a?(Adamas::MIR::Call) && instruction.callee == mir_target.id }
    .not_nil!
    .as(Adamas::MIR::Call)
  mir_callback = mir_caller.blocks
    .flat_map(&.instructions)
    .find { |instruction| instruction.is_a?(Adamas::MIR::FuncPointer) && instruction.func_name == "once_callback" }
    .not_nil!
    .as(Adamas::MIR::FuncPointer)
  OnceRawCallbackObservation.new(mir_call, mir_callback, raw_callback_parameter_id, mir_caller, mir_target, mir_mod.type_registry)
end

describe Adamas::MIR::HIRToMIRLowering do
  it "passes a directly constructed null-environment Proc as a raw yield callback" do
    observed = lower_once_raw_callback_case
    observed.target.params.size.should eq(1)
    observed.target.params[0].type.should eq(Adamas::MIR::TypeRef::POINTER)
    observed.call.args.size.should eq(1)
    observed.call.args[0].should eq(observed.callback_pointer.id)
  end

  it "proves the casted integer-zero environment used by Pointer(Void).null" do
    observed = lower_once_raw_callback_case(opaque_block_formal: true, cast_null_env: true)
    observed.target.params[0].type.should eq(Adamas::MIR::TypeRef::POINTER)
    observed.call.args[0].should eq(observed.callback_pointer.id)
  end

  it "rejects a casted nonzero environment for a generic raw Proc formal" do
    observed = lower_once_raw_callback_case(opaque_block_formal: true, cast_null_env: true, env_value: 1_i64)
    observed.call.args[0].should_not eq(observed.callback_pointer.id)
  end

  it "unwraps a typed null-environment MakeProc around a copied raw callback parameter" do
    observed = lower_once_raw_callback_case(copied_raw_pointer_parameter: true)
    observed.target.params.size.should eq(1)
    observed.target.params[0].type.should eq(Adamas::MIR::TypeRef::POINTER)
    observed.call.args.size.should eq(1)
    observed.call.args[0].should eq(observed.raw_callback_parameter_id.not_nil!)
  end

  it "bitcasts a proven Pointer(Void) raw callback to the selected raw pointer formal" do
    observed = lower_once_raw_callback_case(copied_raw_pointer_parameter: true, pointer_void_parameter: true)
    source_type = observed.caller.params.find { |param| param.name == "callback" }.not_nil!.type
    source_type.should_not eq(Adamas::MIR::TypeRef::POINTER)
    observed.target.params[0].type.should eq(Adamas::MIR::TypeRef::POINTER)

    adapted_instruction = observed.caller.blocks
      .flat_map(&.instructions)
      .find { |instruction| instruction.id == observed.call.args[0] }
    adapted_instruction.should be_a(Adamas::MIR::Cast)
    adapted = adapted_instruction.as(Adamas::MIR::Cast)
    adapted.kind.should eq(Adamas::MIR::CastKind::Bitcast)
    adapted.value.should eq(observed.raw_callback_parameter_id.not_nil!)
    adapted.type.should eq(observed.target.params[0].type)
  end

  it "does not unbox a Pointer(Void) callback for a selected heap-block formal" do
    observed = lower_once_raw_callback_case(
      heap_callee: true,
      copied_raw_pointer_parameter: true,
      pointer_void_parameter: true
    )
    observed.call.args[0].should_not eq(observed.raw_callback_parameter_id.not_nil!)
    observed.caller.blocks
      .flat_map(&.instructions)
      .find { |instruction| instruction.id == observed.call.args[0] }
      .should_not be_a(Adamas::MIR::Cast)
  end

  it "does not bitcast a Pointer(Void) callback when its Proc environment is non-null" do
    observed = lower_once_raw_callback_case(
      env_value: 1_i64,
      copied_raw_pointer_parameter: true,
      pointer_void_parameter: true,
      cast_null_env: true
    )
    observed.call.args[0].should_not eq(observed.raw_callback_parameter_id.not_nil!)
    observed.caller.blocks
      .flat_map(&.instructions)
      .find { |instruction| instruction.id == observed.call.args[0] }
      .should_not be_a(Adamas::MIR::Cast)
  end

  it "recognizes an unnamed source &block parameter as the raw yield ABI" do
    observed = lower_once_raw_callback_case(block_param_name: "_")
    observed.target.params.size.should eq(1)
    observed.target.params[0].type.should eq(Adamas::MIR::TypeRef::POINTER)
    observed.call.args.size.should eq(1)
    observed.call.args[0].should eq(observed.callback_pointer.id)
  end

  it "unwraps a null-environment Proc passed to an opaque pointer block formal that yields it" do
    observed = lower_once_raw_callback_case(opaque_block_formal: true)
    observed.target.params[0].type.should eq(Adamas::MIR::TypeRef::POINTER)
    observed.call.args[0].should eq(observed.callback_pointer.id)
  end

  it "checks an opaque block formal's yielded argument shape against the Proc descriptor" do
    observed = lower_once_raw_callback_case(opaque_block_formal: true, mismatch_signature: true)
    observed.call.args[0].should_not eq(observed.callback_pointer.id)
  end

  it "keeps a null-environment Proc object for a selected heap-block formal" do
    observed = lower_once_raw_callback_case(heap_callee: true)
    observed.call.args.size.should eq(1)
    observed.call.args[0].should_not eq(observed.callback_pointer.id)
  end

  it "does not unbox an opaque pointer block formal selected for heap calls" do
    observed = lower_once_raw_callback_case(heap_callee: true, opaque_block_formal: true)
    observed.target.params[0].type.should eq(Adamas::MIR::TypeRef::POINTER)
    observed.call.args[0].should_not eq(observed.callback_pointer.id)
  end

  it "does not unbox a Proc with a non-null environment into a raw formal" do
    observed = lower_once_raw_callback_case(env_value: 1_i64)
    observed.call.args[0].should_not eq(observed.callback_pointer.id)
  end

  it "does not unbox a non-null Proc for an opaque pointer block formal" do
    observed = lower_once_raw_callback_case(env_value: 1_i64, opaque_block_formal: true)
    observed.call.args[0].should_not eq(observed.callback_pointer.id)
  end

  it "does not unbox a Proc whose declared callback signature differs from the formal" do
    observed = lower_once_raw_callback_case(mismatch_signature: true)
    observed.call.args[0].should_not eq(observed.callback_pointer.id)
  end

  it "does not unbox a callback function whose signature differs from its Proc descriptor" do
    observed = lower_once_raw_callback_case(mismatch_callback_signature: true)
    observed.call.args[0].should_not eq(observed.callback_pointer.id)
  end

  it "keeps a Proc parameter in the object ABI when the method never yields it" do
    observed = lower_once_raw_callback_case(yield_to_block: false)
    observed.target.params[0].type.should_not eq(Adamas::MIR::TypeRef::POINTER)
    observed.call.args[0].should_not eq(observed.callback_pointer.id)
  end

  it "does not treat a copied Proc value as direct MakeProc provenance" do
    observed = lower_once_raw_callback_case(copy_proc: true)
    observed.call.args[0].should_not eq(observed.callback_pointer.id)
  end
end
