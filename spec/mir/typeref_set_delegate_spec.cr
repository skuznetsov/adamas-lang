require "../spec_helper"
require "../../src/compiler/mir/mir"
require "../../src/compiler/mir/hir_to_mir"
require "../../src/compiler/mir/optimizations"
require "../../src/compiler/mir/llvm_backend"

private def typeref_set_call_module : Adamas::MIR::Module
  mod = Adamas::MIR::Module.new("typeref_set_call_identity")
  registry = mod.type_registry

  type_ref_set_type = registry.create_type(
    Adamas::MIR::TypeKind::Reference,
    "Set(Adamas::HIR::TypeRef)",
    8,
    8
  )
  uint32_set_type = registry.create_type(
    Adamas::MIR::TypeKind::Reference,
    "Set(UInt32)",
    8,
    8
  )
  type_ref_array_type = registry.create_type(
    Adamas::MIR::TypeKind::Reference,
    "Array(Adamas::HIR::TypeRef)",
    8,
    8
  )
  uint32_array_type = registry.create_type(
    Adamas::MIR::TypeKind::Reference,
    "Array(UInt32)",
    8,
    8
  )
  value_id_set_type = registry.create_type(
    Adamas::MIR::TypeKind::Reference,
    "Set(Adamas::HIR::ValueId)",
    8,
    8
  )

  type_ref_set = Adamas::MIR::TypeRef.new(type_ref_set_type.id)
  uint32_set = Adamas::MIR::TypeRef.new(uint32_set_type.id)
  type_ref_array = Adamas::MIR::TypeRef.new(type_ref_array_type.id)
  uint32_array = Adamas::MIR::TypeRef.new(uint32_array_type.id)
  value_id_set = Adamas::MIR::TypeRef.new(value_id_set_type.id)

  type_ref_to_a = mod.create_function("Set(Adamas::HIR::TypeRef)#to_a", type_ref_array)
  type_ref_to_a.add_param("self", type_ref_set)
  type_ref_to_a_builder = Adamas::MIR::Builder.new(type_ref_to_a)
  type_ref_to_a_builder.ret(0_u32)

  uint32_to_a = mod.create_function("Set(UInt32)#to_a", uint32_array)
  uint32_to_a.add_param("self", uint32_set)
  uint32_to_a_builder = Adamas::MIR::Builder.new(uint32_to_a)
  uint32_to_a_builder.ret(0_u32)

  uint32_new = mod.create_function("Set(UInt32).new", uint32_set)
  uint32_new.add_param("seed", uint32_set)
  uint32_new_builder = Adamas::MIR::Builder.new(uint32_new)
  uint32_new_builder.ret(0_u32)

  rooted_type_ref_new = mod.create_function("::Set(Adamas::HIR::TypeRef).new", type_ref_set)
  rooted_type_ref_new.add_param("seed", type_ref_set)
  rooted_type_ref_new_builder = Adamas::MIR::Builder.new(rooted_type_ref_new)
  rooted_type_ref_new_builder.ret(0_u32)

  rooted_value_id_new = mod.create_function("::Set(Adamas::HIR::ValueId).new", value_id_set)
  rooted_value_id_new.add_param("seed", value_id_set)
  rooted_value_id_new_builder = Adamas::MIR::Builder.new(rooted_value_id_new)
  rooted_value_id_new_builder.ret(0_u32)

  direct_caller = mod.create_function("call_typeref_set_to_a_direct", type_ref_array)
  direct_caller.add_param("set", type_ref_set)
  direct_builder = Adamas::MIR::Builder.new(direct_caller)
  direct_result = direct_builder.call(
    type_ref_to_a.id,
    [0_u32] of Adamas::MIR::ValueId,
    type_ref_array
  )
  direct_builder.ret(direct_result)

  extern_caller = mod.create_function("call_typeref_set_to_a_extern", type_ref_array)
  extern_caller.add_param("set", type_ref_set)
  extern_builder = Adamas::MIR::Builder.new(extern_caller)
  extern_result = extern_builder.extern_call(
    "Set(Adamas::HIR::TypeRef)#to_a",
    [0_u32] of Adamas::MIR::ValueId,
    type_ref_array
  )
  extern_builder.ret(extern_result)

  uint32_caller = mod.create_function("call_uint32_set_to_a", uint32_array)
  uint32_caller.add_param("set", uint32_set)
  uint32_builder = Adamas::MIR::Builder.new(uint32_caller)
  uint32_result = uint32_builder.call(
    uint32_to_a.id,
    [0_u32] of Adamas::MIR::ValueId,
    uint32_array
  )
  uint32_builder.ret(uint32_result)

  mod
end

describe "Set(TypeRef) LLVM call identity" do
  it "does not retarget wrapper-element Set calls to Set(UInt32)" do
    mod = typeref_set_call_module
    generator = Adamas::MIR::LLVMIRGenerator.new(mod)
    generator.emit_type_metadata = false
    output = generator.generate

    direct = output[/define ptr @call_typeref_set_to_a_direct\([^)]*\)\s*\{.*?\n\}/m].not_nil!
    direct.should contain("call ptr @Set$LAdamas$CCHIR$CCTypeRef$R$Hto_a")
    direct.should_not contain("call ptr @Set$LUInt32$R$Hto_a")

    extern = output[/define ptr @call_typeref_set_to_a_extern\([^)]*\)\s*\{.*?\n\}/m].not_nil!
    extern.should contain("call ptr @Set$LAdamas$CCHIR$CCTypeRef$R$Hto_a")
    extern.should_not contain("call ptr @Set$LUInt32$R$Hto_a")

    uint32 = output[/define ptr @call_uint32_set_to_a\([^)]*\)\s*\{.*?\n\}/m].not_nil!
    uint32.should contain("call ptr @Set$LUInt32$R$Hto_a")

    rooted_type_ref_new = output[/define ptr @\$CCSet\$LAdamas\$CCHIR\$CCTypeRef\$R\$Dnew\([^)]*\)\s*\{.*?\n\}/m].not_nil!
    rooted_type_ref_new.should contain("ret ptr %seed")
    rooted_type_ref_new.should_not contain("call ptr @Set$LUInt32$R$Dnew")

    rooted_value_id_new = output[/define ptr @\$CCSet\$LAdamas\$CCHIR\$CCValueId\$R\$Dnew\([^)]*\)\s*\{.*?\n\}/m].not_nil!
    rooted_value_id_new.should contain("call ptr @Set$LUInt32$R$Dnew")
  end
end
