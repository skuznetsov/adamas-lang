require "../spec_helper"
require "../../src/compiler/hir/hir"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/mir/mir"
require "../../src/compiler/mir/hir_to_mir"
require "../../src/compiler/mir/optimizations"
require "../../src/compiler/mir/llvm_backend"

private record PointerUnionMIRFixture,
  hir_module : Adamas::HIR::Module,
  pointer_u8 : Adamas::HIR::TypeRef,
  pointer_void : Adamas::HIR::TypeRef,
  union_type : Adamas::HIR::TypeRef,
  mir_union_type : Adamas::MIR::TypeRef,
  descriptor : Adamas::MIR::UnionDescriptor

private def pointer_union_mir_fixture(mixed : Bool = true) : PointerUnionMIRFixture
  hir_mod = Adamas::HIR::Module.new("pointer_union_mir")
  pointer_u8 = hir_mod.intern_type(
    Adamas::HIR::TypeDescriptor.new(
      Adamas::HIR::TypeKind::Pointer,
      "Pointer(UInt8)",
      [Adamas::HIR::TypeRef::UINT8]
    )
  )
  pointer_void = hir_mod.intern_type(
    Adamas::HIR::TypeDescriptor.new(
      Adamas::HIR::TypeKind::Pointer,
      "Pointer(Void)",
      [Adamas::HIR::TypeRef::VOID]
    )
  )
  union_name = mixed ? "Pointer(UInt8) | Int32" : "Pointer(UInt8) | Pointer(Void)"
  union_type = hir_mod.intern_type(
    Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Union, union_name)
  )
  mir_union_type = Adamas::MIR::TypeRef.from_hir(union_type)
  variants = [
    Adamas::MIR::UnionVariantDescriptor.new(
      type_id: 37,
      type_ref: Adamas::MIR::TypeRef.from_hir(pointer_u8),
      full_name: "Pointer(UInt8)",
      size: 8,
      alignment: 8,
      field_offsets: nil
    ),
  ] of Adamas::MIR::UnionVariantDescriptor
  if mixed
    variants << Adamas::MIR::UnionVariantDescriptor.new(
      type_id: 143,
      type_ref: Adamas::MIR::TypeRef::INT32,
      full_name: "Int32",
      size: 4,
      alignment: 4,
      field_offsets: nil
    )
  else
    variants << Adamas::MIR::UnionVariantDescriptor.new(
      type_id: 91,
      type_ref: Adamas::MIR::TypeRef.from_hir(pointer_void),
      full_name: "Pointer(Void)",
      size: 8,
      alignment: 8,
      field_offsets: nil
    )
  end
  descriptor = Adamas::MIR::UnionDescriptor.new(union_name, variants, 32, 8)
  PointerUnionMIRFixture.new(hir_mod, pointer_u8, pointer_void, union_type, mir_union_type, descriptor)
end

private def lower_pointer_union_store_fixture(
  fixture : PointerUnionMIRFixture,
  explicit_unwrap : Bool,
  select_void : Bool = false,
) : Adamas::MIR::Module
  hir_mod = fixture.hir_module
  func_name = explicit_unwrap ? "tagged_pointer_union_store" : "mixed_pointer_union_store"
  func = hir_mod.create_function(func_name, Adamas::HIR::TypeRef::VOID)
  pointer = func.add_param("pointer", fixture.union_type)
  value = func.add_param("value", Adamas::HIR::TypeRef::INT32)
  index = func.add_param("index", Adamas::HIR::TypeRef::INT32)
  block = func.get_block(func.entry_block)
  pointer_id = pointer.id
  if explicit_unwrap
    selected = Adamas::HIR::UnionUnwrap.new(
      func.next_value_id,
      select_void ? fixture.pointer_void : fixture.pointer_u8,
      pointer.id,
      select_void ? 91 : 37,
      false
    )
    block.add(selected)
    pointer_id = selected.id
  end
  store = Adamas::HIR::PointerStore.new(
    func.next_value_id,
    Adamas::HIR::TypeRef::VOID,
    pointer_id,
    value.id,
    index.id
  )
  block.add(store)
  block.terminator = Adamas::HIR::Return.new

  lowering = Adamas::MIR::HIRToMIRLowering.new(hir_mod)
  lowering.register_container_types(hir_mod.types)
  lowering.register_union_types([
    Adamas::HIR::UnionDescriptorRegistration.new(fixture.mir_union_type, fixture.descriptor),
  ])
  lowering.lower
end

describe Adamas::MIR::HIRToMIRLowering do
  it "extracts the selected tagged pointer payload before GEP and Store" do
    fixture = pointer_union_mir_fixture
    mir_mod = lower_pointer_union_store_fixture(fixture, true)
    mir_func = mir_mod.functions.find { |function| function.name == "tagged_pointer_union_store" }.not_nil!
    instructions = mir_func.blocks.flat_map(&.instructions)

    unwrap = instructions.find { |instruction| instruction.is_a?(Adamas::MIR::UnionUnwrap) }
    unwrap.should_not be_nil
    unwrap = unwrap.not_nil!.as(Adamas::MIR::UnionUnwrap)
    unwrap.variant_type_id.should eq(37)
    unwrap.type.should eq(Adamas::MIR::TypeRef.from_hir(fixture.pointer_u8))

    gep = instructions.find { |instruction| instruction.is_a?(Adamas::MIR::GetElementPtrDynamic) }
    gep.should_not be_nil
    gep = gep.not_nil!.as(Adamas::MIR::GetElementPtrDynamic)
    gep.base.should eq(unwrap.id)
    store = instructions.find { |instruction| instruction.is_a?(Adamas::MIR::Store) }
    store.should_not be_nil
    store.not_nil!.as(Adamas::MIR::Store).ptr.should eq(gep.id)
  end

  it "uses the Int32 payload stride for an explicit Pointer(Void) indexed store" do
    fixture = pointer_union_mir_fixture(false)
    mir_mod = lower_pointer_union_store_fixture(fixture, true, true)
    mir_func = mir_mod.functions.find { |function| function.name == "tagged_pointer_union_store" }.not_nil!
    instructions = mir_func.blocks.flat_map(&.instructions)

    unwrap = instructions.find { |instruction| instruction.is_a?(Adamas::MIR::UnionUnwrap) }
    unwrap.should_not be_nil
    unwrap = unwrap.not_nil!.as(Adamas::MIR::UnionUnwrap)
    unwrap.variant_type_id.should eq(91)
    unwrap.type.should eq(Adamas::MIR::TypeRef.from_hir(fixture.pointer_void))

    gep = instructions.find { |instruction| instruction.is_a?(Adamas::MIR::GetElementPtrDynamic) }
    gep.should_not be_nil
    gep = gep.not_nil!.as(Adamas::MIR::GetElementPtrDynamic)
    gep.element_type.should eq(Adamas::MIR::TypeRef::INT32)
    gep.element_byte_size.should eq(4_u64)
    store = instructions.find { |instruction| instruction.is_a?(Adamas::MIR::Store) }
    store.should_not be_nil
    store.not_nil!.as(Adamas::MIR::Store).field_type.should eq(Adamas::MIR::TypeRef::INT32)
  end

  it "emits tagged-union payload extraction as a union alloca and payload GEP" do
    fixture = pointer_union_mir_fixture
    mir_mod = lower_pointer_union_store_fixture(fixture, true)
    generator = Adamas::MIR::LLVMIRGenerator.new(mir_mod)
    generator.emit_type_metadata = false
    output = generator.generate
    body = output[/define void @tagged_pointer_union_store\([^)]*\)\s*\{.*?\n\}/m]
    body.should_not be_nil
    body = body.not_nil!
    body.should match(/union_ptr = alloca %Pointer\$LUInt8\$R\$_\$OR\$_Int32\.union/)
    body.should match(/payload_ptr = getelementptr %Pointer\$LUInt8\$R\$_\$OR\$_Int32\.union/)
    body.should match(/load ptr, ptr %[^\n]*payload_ptr/)
  end
end
