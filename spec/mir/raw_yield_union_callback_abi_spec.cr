require "../spec_helper"
require "../../src/compiler/hir/hir"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/hir/escape_analysis"
require "../../src/compiler/hir/taint_analysis"
require "../../src/compiler/hir/memory_strategy"
require "../../src/compiler/mir/mir"
require "../../src/compiler/mir/hir_to_mir"

private enum RawYieldBlockMode
  NullableProc
  DirectProc
  MissingSignature
  AmbiguousSignature
end

private def lower_raw_yield_case(
  actual_union_args : Array(Bool),
  callback_union_args : Array(Bool),
  block_mode : RawYieldBlockMode = RawYieldBlockMode::NullableProc,
  callback_concrete_types : Array(Adamas::HIR::TypeRef)? = nil,
) : {Adamas::MIR::IndirectCall, Array(Adamas::MIR::Value)}
  actual_union_args.size.should eq(callback_union_args.size)
  if concrete_types = callback_concrete_types
    concrete_types.size.should eq(callback_union_args.size)
  end

  hir_mod = Adamas::HIR::Module.new("raw_yield_union_callback_abi")
  union_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
    Adamas::HIR::TypeKind::Union,
    "Nil | Int32"
  ))

  callback_params = [] of Adamas::HIR::TypeRef
  callback_union_args.each_with_index do |is_union, index|
    concrete_type = callback_concrete_types.try(&.unsafe_fetch(index)) || Adamas::HIR::TypeRef::INT32
    callback_params << (is_union ? union_ref : concrete_type)
  end
  proc_type_params = callback_params.dup
  proc_type_params << Adamas::HIR::TypeRef::INT32
  proc_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
    Adamas::HIR::TypeKind::Proc,
    "Proc(raw_yield_callback)",
    proc_type_params
  ))

  alternate_proc_ref : Adamas::HIR::TypeRef? = nil
  if block_mode == RawYieldBlockMode::AmbiguousSignature
    # Keep two distinct Proc refs in the registered union. The non-Proc-shaped
    # union name lets lowering reach the indirect call while its signature
    # lookup still has to reject the ambiguous callback contract.
    alternate_proc_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
      Adamas::HIR::TypeKind::Proc,
      "Proc(raw_yield_callback_alt)",
      proc_type_params
    ))
  end

  block_ref = case block_mode
              when RawYieldBlockMode::MissingSignature
                # A pointer carrier has no HIR callback descriptor to consult.
                Adamas::HIR::TypeRef::POINTER
              when RawYieldBlockMode::DirectProc
                proc_ref
              when RawYieldBlockMode::AmbiguousSignature
                hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
                  Adamas::HIR::TypeKind::Union,
                  "Nil | Callback"
                ))
              else
                hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
                  Adamas::HIR::TypeKind::Union,
                  "Nil | Proc(raw_yield_callback)"
                ))
              end

  func = hir_mod.create_function("invoke$raw_yield_case", Adamas::HIR::TypeRef::INT32)
  block_param = func.add_param("block", block_ref, true)
  actual_params = actual_union_args.map_with_index do |is_union, index|
    type = is_union ? union_ref : Adamas::HIR::TypeRef::INT32
    func.add_param("value#{index}", type)
  end
  block = func.get_block(func.entry_block)
  yld = Adamas::HIR::Yield.new(
    func.next_value_id,
    Adamas::HIR::TypeRef::INT32,
    actual_params.map(&.id),
    block_param.id
  )
  block.add(yld)
  block.terminator = Adamas::HIR::Return.new(yld.id)

  block_variants = [
    Adamas::MIR::UnionVariantDescriptor.new(
      1,
      Adamas::MIR::TypeRef.from_hir(proc_ref),
      "Proc(raw_yield_callback)",
      8,
      8,
      nil
    ),
  ] of Adamas::MIR::UnionVariantDescriptor
  if alternate_proc = alternate_proc_ref
    block_variants << Adamas::MIR::UnionVariantDescriptor.new(
      2,
      Adamas::MIR::TypeRef.from_hir(alternate_proc),
      "Proc(raw_yield_callback_alt)",
      8,
      8,
      nil
    )
  end
  block_variants << Adamas::MIR::UnionVariantDescriptor.new(
    0,
    Adamas::MIR::TypeRef::NIL,
    "Nil",
    0,
    1,
    nil
  )
  block_descriptor = Adamas::MIR::UnionDescriptor.new(
    block_mode == RawYieldBlockMode::AmbiguousSignature ? "Nil | Callback" : "Nil | Proc(raw_yield_callback)",
    block_variants,
    16,
    8
  )
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
  registrations = [] of Adamas::HIR::UnionDescriptorRegistration
  if block_mode == RawYieldBlockMode::NullableProc || block_mode == RawYieldBlockMode::AmbiguousSignature
    registrations << Adamas::HIR::UnionDescriptorRegistration.new(
      Adamas::MIR::TypeRef.from_hir(block_ref),
      block_descriptor
    )
  end
  if actual_union_args.any? { |is_union| is_union } || callback_union_args.any? { |is_union| is_union }
    registrations << Adamas::HIR::UnionDescriptorRegistration.new(
      Adamas::MIR::TypeRef.from_hir(union_ref),
      union_descriptor
    )
  end
  lowering.register_union_types(registrations)

  mir_mod = lowering.lower
  mir_func = mir_mod.functions.find { |candidate| candidate.name == "invoke$raw_yield_case" }.not_nil!
  instructions = mir_func.blocks
    .flat_map(&.instructions)
  indirect = instructions
    .select(&.is_a?(Adamas::MIR::IndirectCall))
    .first
    .not_nil!
    .as(Adamas::MIR::IndirectCall)
  {indirect, instructions}
end

describe Adamas::MIR::HIRToMIRLowering do
  it "preserves a yielded union when the raw callback formal expects that union" do
    indirect, _ = lower_raw_yield_case([true], [true])
    indirect.unwrap_union_args.should be_false
  end

  it "uses the direct Proc descriptor as the callback signature" do
    indirect, _ = lower_raw_yield_case(
      [true],
      [true],
      block_mode: RawYieldBlockMode::DirectProc
    )
    indirect.unwrap_union_args.should be_false
  end

  it "unwraps a yielded union when the raw callback formal is concrete" do
    indirect, instructions = lower_raw_yield_case([true], [false])
    indirect.unwrap_union_args.should be_false
    instructions.any? do |instruction|
      instruction.is_a?(Adamas::MIR::UnionUnwrap) &&
        instruction.type == Adamas::MIR::TypeRef::INT32 &&
        indirect.args.includes?(instruction.id)
    end.should be_true
  end

  it "wraps a concrete yielded value when the raw callback formal is a union" do
    indirect, instructions = lower_raw_yield_case([false], [true])
    indirect.unwrap_union_args.should be_false
    instructions.any? do |instruction|
      instruction.is_a?(Adamas::MIR::UnionWrap) &&
        instruction.type == Adamas::MIR::TypeRef.from_hir(
          Adamas::HIR::TypeRef.new(Adamas::HIR::TypeRef::FIRST_USER_TYPE)
        ) &&
        indirect.args.includes?(instruction.id)
    end.should be_true
  end

  it "preserves union arguments alongside ordinary callback arguments" do
    indirect, _ = lower_raw_yield_case([false, true], [false, true])
    indirect.unwrap_union_args.should be_false
  end

  it "keeps the legacy mode when the callback has no union argument" do
    indirect, _ = lower_raw_yield_case([false], [false])
    indirect.unwrap_union_args.should be_true
  end

  it "prepares concrete payloads without stripping a neighboring full union" do
    indirect, instructions = lower_raw_yield_case([true, true], [true, false])
    indirect.unwrap_union_args.should be_false
    instructions.any? do |instruction|
      instruction.is_a?(Adamas::MIR::UnionUnwrap) &&
        instruction.type == Adamas::MIR::TypeRef::INT32 &&
        indirect.args.includes?(instruction.id)
    end.should be_true
  end

  it "keeps legacy mode when a callback signature is missing" do
    indirect, instructions = lower_raw_yield_case(
      [true],
      [true],
      block_mode: RawYieldBlockMode::MissingSignature
    )
    indirect.unwrap_union_args.should be_true
    instructions.any? do |instruction|
      instruction.is_a?(Adamas::MIR::UnionUnwrap) &&
        instruction.variant_type_id == Adamas::MIR::TypeRef::INT32.id.to_i32
    end.should be_false
  end

  it "keeps legacy mode when callback variants make the signature ambiguous" do
    indirect, instructions = lower_raw_yield_case(
      [true],
      [true],
      block_mode: RawYieldBlockMode::AmbiguousSignature
    )
    indirect.unwrap_union_args.should be_true
    instructions.any? do |instruction|
      instruction.is_a?(Adamas::MIR::UnionUnwrap) &&
        instruction.variant_type_id == Adamas::MIR::TypeRef::INT32.id.to_i32
    end.should be_false
  end

  it "does not emit an earlier bridge when a later callback argument is unsupported" do
    indirect, instructions = lower_raw_yield_case(
      [true, true],
      [false, false],
      callback_concrete_types: [
        Adamas::HIR::TypeRef::INT32,
        Adamas::HIR::TypeRef::INT64,
      ]
    )
    indirect.unwrap_union_args.should be_true
    instructions.any? do |instruction|
      instruction.is_a?(Adamas::MIR::UnionUnwrap) &&
        instruction.variant_type_id == Adamas::MIR::TypeRef::INT32.id.to_i32
    end.should be_false
  end
end
