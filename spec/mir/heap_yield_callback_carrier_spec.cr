require "../spec_helper"
require "../../src/compiler/hir/hir"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/mir/mir"
require "../../src/compiler/mir/hir_to_mir"

private struct HeapYieldCallbackObservation
  getter mir_function : Adamas::MIR::Function
  getter block_param_id : Adamas::HIR::ValueId
  getter regular_proc_param_id : Adamas::HIR::ValueId
  getter union_type : Adamas::MIR::TypeRef
  getter instructions : Array(Adamas::MIR::Value)
  getter indirect_calls : Array(Adamas::MIR::IndirectCall)

  def initialize(
    @mir_function : Adamas::MIR::Function,
    @block_param_id : Adamas::HIR::ValueId,
    @regular_proc_param_id : Adamas::HIR::ValueId,
    @union_type : Adamas::MIR::TypeRef,
    @instructions : Array(Adamas::MIR::Value),
    @indirect_calls : Array(Adamas::MIR::IndirectCall),
  )
  end
end

private def lower_heap_yield_callback_case : HeapYieldCallbackObservation
  hir_mod = Adamas::HIR::Module.new("heap_yield_callback_carrier")
  union_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
    Adamas::HIR::TypeKind::Union,
    "Nil | Int32"
  ))
  block_proc_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
    Adamas::HIR::TypeKind::Proc,
    "Proc(Nil | Int32, Nil | Int32)",
    [union_ref, union_ref]
  ))
  regular_proc_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
    Adamas::HIR::TypeKind::Proc,
    "Proc(Int32, Int32)",
    [Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::INT32]
  ))

  target = hir_mod.create_function("HeapYieldCarrier#invoke$block", union_ref)
  target.heap_block_param = true
  regular_proc_param = target.add_param("regular_proc", regular_proc_ref)
  block_param = target.add_param("block", block_proc_ref, true)

  body = target.get_block(target.entry_block)
  concrete_arg = Adamas::HIR::Literal.new(
    target.next_value_id,
    Adamas::HIR::TypeRef::INT32,
    37_i64
  )
  body.add(concrete_arg)
  yielded = Adamas::HIR::Yield.new(
    target.next_value_id,
    union_ref,
    [concrete_arg.id],
    block_param.id
  )
  body.add(yielded)
  body.terminator = Adamas::HIR::Return.new(yielded.id)

  union_mir_ref = Adamas::MIR::TypeRef.from_hir(union_ref)
  union_descriptor = Adamas::MIR::UnionDescriptor.new(
    "Nil | Int32",
    [
      Adamas::MIR::UnionVariantDescriptor.new(
        Adamas::MIR::TypeRef::INT32.id.to_i32,
        Adamas::MIR::TypeRef::INT32,
        "Int32",
        4,
        4,
        nil
      ),
      Adamas::MIR::UnionVariantDescriptor.new(
        0,
        Adamas::MIR::TypeRef::NIL,
        "Nil",
        0,
        1,
        nil
      ),
    ],
    16,
    8
  )

  lowering = Adamas::MIR::HIRToMIRLowering.new(hir_mod)
  lowering.register_union_types([
    Adamas::HIR::UnionDescriptorRegistration.new(union_mir_ref, union_descriptor),
  ])
  mir_mod = lowering.lower
  mir_function = mir_mod.functions.find { |candidate| candidate.name == target.name }.not_nil!
  instructions = mir_function.blocks.flat_map(&.instructions)
  indirect_calls = instructions.select(&.is_a?(Adamas::MIR::IndirectCall)).map(&.as(Adamas::MIR::IndirectCall))

  HeapYieldCallbackObservation.new(
    mir_function,
    block_param.id,
    regular_proc_param.id,
    union_mir_ref,
    instructions,
    indirect_calls
  )
end

private def heap_yield_union_registration(
  type_ref : Adamas::HIR::TypeRef,
  name : String,
  include_nil : Bool,
) : Adamas::HIR::UnionDescriptorRegistration
  variants = [
    Adamas::MIR::UnionVariantDescriptor.new(
      Adamas::MIR::TypeRef::INT32.id.to_i32,
      Adamas::MIR::TypeRef::INT32,
      "Int32",
      4,
      4,
      nil
    ),
    Adamas::MIR::UnionVariantDescriptor.new(
      Adamas::MIR::TypeRef::STRING.id.to_i32,
      Adamas::MIR::TypeRef::STRING,
      "String",
      8,
      8,
      nil
    ),
  ] of Adamas::MIR::UnionVariantDescriptor
  if include_nil
    variants << Adamas::MIR::UnionVariantDescriptor.new(
      0,
      Adamas::MIR::TypeRef::NIL,
      "Nil",
      0,
      1,
      nil
    )
  end

  descriptor = Adamas::MIR::UnionDescriptor.new(name, variants, 16, 8)
  Adamas::HIR::UnionDescriptorRegistration.new(
    Adamas::MIR::TypeRef.from_hir(type_ref),
    descriptor
  )
end

private def build_heap_yield_guard_case(
  hir_mod : Adamas::HIR::Module,
  name : String,
  actual_types : Array(Adamas::HIR::TypeRef),
  callback_arg_types : Array(Adamas::HIR::TypeRef)?,
  union_registrations : Array(Adamas::HIR::UnionDescriptorRegistration) = [] of Adamas::HIR::UnionDescriptorRegistration,
  tuple_to_allocate : Adamas::HIR::TypeRef? = nil,
) : Adamas::MIR::HIRToMIRLowering
  block_type = if callback_types = callback_arg_types
                 proc_types = callback_types.dup
                 proc_types << Adamas::HIR::TypeRef::INT32
                 hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
                   Adamas::HIR::TypeKind::Proc,
                   "Proc(#{name})",
                   proc_types
                 ))
               else
                 # A raw pointer has no callback descriptor to validate.
                 Adamas::HIR::TypeRef::POINTER
               end

  target = hir_mod.create_function("#{name}#invoke", Adamas::HIR::TypeRef::INT32)
  target.heap_block_param = true
  actual_params = actual_types.map_with_index do |type, index|
    target.add_param("value#{index}", type)
  end
  block_param = target.add_param("block", block_type, true)

  body = target.get_block(target.entry_block)
  args = actual_params.map(&.id)
  if tuple_type = tuple_to_allocate
    tuple = Adamas::HIR::Allocate.new(target.next_value_id, tuple_type, args, true)
    body.add(tuple)
    args = [tuple.id]
  end
  yielded = Adamas::HIR::Yield.new(
    target.next_value_id,
    Adamas::HIR::TypeRef::INT32,
    args,
    block_param.id
  )
  body.add(yielded)
  body.terminator = Adamas::HIR::Return.new(yielded.id)

  lowering = Adamas::MIR::HIRToMIRLowering.new(hir_mod)
  lowering.register_tuple_types(hir_mod.types)
  lowering.register_union_types(union_registrations)
  lowering
end

private def expect_heap_yield_abi_rejection(
  lowering : Adamas::MIR::HIRToMIRLowering,
  function_name : String,
) : Nil
  expect_raises(Exception, /MIR heap yield argument ABI unresolved/) do
    lowering.lower
  end

  # Lowering must reject before it materializes either arm of the heap Proc
  # indirect-call diamond. This checks the safety boundary, not just the text
  # of the diagnostic.
  mir_function = lowering.mir_module.functions.find { |func| func.name == function_name }.not_nil!
  mir_function.blocks.flat_map(&.instructions).any?(&.is_a?(Adamas::MIR::IndirectCall)).should be_false
end

describe Adamas::MIR::HIRToMIRLowering do
  it "dispatches a targeted heap yield through the Proc environment and raw arms" do
    observed = lower_heap_yield_callback_case

    observed.indirect_calls.size.should eq(2)
    observed.indirect_calls.each do |call|
      call.unwrap_union_args.should be_false
      call.type.should eq(observed.union_type)
    end
    observed.indirect_calls.map(&.args.size).sort.should eq([1, 2])

    # The function has another Proc parameter before its source block parameter.
    # Both indirect calls must load their code pointer from the explicit Yield
    # target, not from an adjacent Proc-shaped argument.
    observed.block_param_id.should_not eq(observed.regular_proc_param_id)
    observed.indirect_calls.each do |call|
      fn_ptr_load_value = observed.instructions
        .find { |instruction| instruction.id == call.callee_ptr }
        .not_nil!
      fn_ptr_load_value.should be_a(Adamas::MIR::Load)
      fn_ptr_load = fn_ptr_load_value.as(Adamas::MIR::Load)
      fn_ptr_gep_value = observed.instructions
        .find { |instruction| instruction.id == fn_ptr_load.ptr }
        .not_nil!
      fn_ptr_gep_value.should be_a(Adamas::MIR::GetElementPtr)
      fn_ptr_gep = fn_ptr_gep_value.as(Adamas::MIR::GetElementPtr)
      fn_ptr_gep.base.should eq(observed.block_param_id)
      fn_ptr_gep.base.should_not eq(observed.regular_proc_param_id)
    end

    # A concrete yielded Int32 is adapted to the callback's declared union
    # input, and both callback paths retain the union return ABI.
    wrap = observed.instructions
      .select(&.is_a?(Adamas::MIR::UnionWrap))
      .map(&.as(Adamas::MIR::UnionWrap))
      .find { |candidate| candidate.type == observed.union_type }
      .not_nil!
    observed.indirect_calls.each { |call| call.args.should contain(wrap.id) }
    observed.instructions.any? do |instruction|
      instruction.is_a?(Adamas::MIR::Phi) && instruction.type == observed.union_type
    end.should be_true
  end

  it "rejects heap yields without a callback signature before emitting indirect calls" do
    hir_mod = Adamas::HIR::Module.new("HeapYieldUnknownSignature")
    lowering = build_heap_yield_guard_case(
      hir_mod,
      "HeapYieldUnknownSignature",
      [Adamas::HIR::TypeRef::INT32],
      nil
    )

    expect_heap_yield_abi_rejection(lowering, "HeapYieldUnknownSignature#invoke")
  end

  it "rejects a VOID-typed yielded actual for a union callback formal" do
    hir_mod = Adamas::HIR::Module.new("HeapYieldVoidActual")
    union_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
      Adamas::HIR::TypeKind::Union,
      "Int32 | String | Nil"
    ))
    formal_union = heap_yield_union_registration(
      union_ref,
      "Int32 | String | Nil",
      true
    )
    lowering = build_heap_yield_guard_case(
      hir_mod,
      "HeapYieldVoidActual",
      [Adamas::HIR::TypeRef::VOID],
      [union_ref],
      [formal_union]
    )

    expect_heap_yield_abi_rejection(lowering, "HeapYieldVoidActual#invoke")
  end

  it "rejects distinct union callback layouts before emitting indirect calls" do
    hir_mod = Adamas::HIR::Module.new("HeapYieldDistinctUnion")
    actual_union = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
      Adamas::HIR::TypeKind::Union,
      "Int32 | String"
    ))
    formal_union = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
      Adamas::HIR::TypeKind::Union,
      "Int32 | String | Nil"
    ))
    registrations = [
      heap_yield_union_registration(actual_union, "Int32 | String", false),
      heap_yield_union_registration(formal_union, "Int32 | String | Nil", true),
    ]
    lowering = build_heap_yield_guard_case(
      hir_mod,
      "HeapYieldDistinctUnion",
      [actual_union],
      [formal_union],
      registrations
    )

    expect_heap_yield_abi_rejection(lowering, "HeapYieldDistinctUnion#invoke")
  end

  it "retains a constructed tuple's exact type on both heap callback arms" do
    hir_mod = Adamas::HIR::Module.new("ConstructedTuple")
    elements = [Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::INT32]
    tuple = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
      Adamas::HIR::TypeKind::Tuple, "Tuple(Int32, Int32)", elements
    ))
    lowering = build_heap_yield_guard_case(hir_mod, "ConstructedTuple", elements, [tuple], tuple_to_allocate: tuple)
    ir = lowering.lower.functions.find { |fn| fn.name == "ConstructedTuple#invoke" }.not_nil!
    instructions = ir.blocks.flat_map(&.instructions)
    calls = instructions.select(Adamas::MIR::IndirectCall)
    calls.size.should eq(2)
    yielded = calls.map(&.args.last).uniq
    yielded.size.should eq(1)
    instructions.find { |inst| inst.id == yielded.first }.not_nil!.type.should eq(Adamas::MIR::TypeRef.from_hir(tuple))
  end

  it "rejects a raw pointer and a same-size tuple with different elements as a tuple argument" do
    hir_mod = Adamas::HIR::Module.new("DistinctTuples")
    elements = [Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::INT32]
    pair = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
      Adamas::HIR::TypeKind::Tuple, "Tuple(Int32, Int32)", elements
    ))
    different = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
      Adamas::HIR::TypeKind::Tuple, "Tuple(Int32, UInt32)", [elements.first, Adamas::HIR::TypeRef::UINT32]
    ))
    mismatch = build_heap_yield_guard_case(hir_mod, "DistinctTuples", elements, [different], tuple_to_allocate: pair)
    expect_heap_yield_abi_rejection(mismatch, "DistinctTuples#invoke")

    raw_mod = Adamas::HIR::Module.new("RawAddress")
    pair = raw_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
      Adamas::HIR::TypeKind::Tuple, "Tuple(Int32, Int32)", elements
    ))
    raw = build_heap_yield_guard_case(raw_mod, "RawAddress", [Adamas::HIR::TypeRef::POINTER], [pair])
    expect_heap_yield_abi_rejection(raw, "RawAddress#invoke")
  end

  it "rejects a scalar actual whose MIR ABI differs from the callback formal" do
    hir_mod = Adamas::HIR::Module.new("HeapYieldScalarAbiMismatch")
    lowering = build_heap_yield_guard_case(
      hir_mod,
      "HeapYieldScalarAbiMismatch",
      [Adamas::HIR::TypeRef::INT32],
      [Adamas::HIR::TypeRef::INT64]
    )

    expect_heap_yield_abi_rejection(lowering, "HeapYieldScalarAbiMismatch#invoke")
  end
end
