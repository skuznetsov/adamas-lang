require "../spec_helper"
require "../../src/compiler/hir/hir"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/mir/mir"
require "../../src/compiler/mir/hir_to_mir"

class Adamas::MIR::HIRToMIRLowering
  def __test_macro_nullable_virtual_resolution(
    class_name : String,
    method_suffix : String,
    arg_count : Int32,
  ) : Adamas::MIR::Function?
    resolve_virtual_method_for_class(class_name, method_suffix, arg_count)
  end
end

private def macro_nullable_union(
  hir_mod : Adamas::HIR::Module,
  name : String,
  extra_type : Adamas::HIR::TypeRef,
) : Adamas::HIR::TypeRef
  hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
    Adamas::HIR::TypeKind::Union,
    name,
    [Adamas::HIR::TypeRef::NIL, extra_type]
  ))
end

private def macro_hash_type(
  hir_mod : Adamas::HIR::Module,
  name : String,
  value_type : Adamas::HIR::TypeRef,
) : Adamas::HIR::TypeRef
  hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
    Adamas::HIR::TypeKind::Hash,
    name,
    [Adamas::HIR::TypeRef::STRING, value_type]
  ))
end

private def macro_nullable_union_registration(
  hir_ref : Adamas::HIR::TypeRef,
  name : String,
  extra_type : Adamas::HIR::TypeRef,
) : Adamas::HIR::UnionDescriptorRegistration
  mir_ref = Adamas::MIR::TypeRef.from_hir(hir_ref)
  extra_mir_type = Adamas::MIR::TypeRef.from_hir(extra_type)
  Adamas::HIR::UnionDescriptorRegistration.new(
    mir_ref,
    Adamas::MIR::UnionDescriptor.new(
      name,
      [
        Adamas::MIR::UnionVariantDescriptor.new(
          Adamas::MIR::TypeRef::NIL.id.to_i32,
          Adamas::MIR::TypeRef::NIL,
          "Nil",
          0,
          1,
          nil
        ),
        Adamas::MIR::UnionVariantDescriptor.new(
          extra_mir_type.id.to_i32,
          extra_mir_type,
          name.split(" | ").last,
          8,
          8,
          nil
        ),
      ],
      16,
      8
    )
  )
end

private def add_macro_method_params(
  func : Adamas::HIR::Function,
  named_args_type : Adamas::HIR::TypeRef,
  self_type : Adamas::HIR::TypeRef = Adamas::HIR::TypeRef::POINTER,
) : Nil
  func.add_param("self", self_type)
  func.add_param("name", Adamas::HIR::TypeRef::STRING)
  func.add_param("args", Adamas::HIR::TypeRef::POINTER)
  func.add_param("named_args", named_args_type)
end

describe "nullable virtual override selection" do
  it "prefers a child union parameter that accepts the exact ancestor Nil argument" do
    hir_mod = Adamas::HIR::Module.new("macro_nullable_virtual_override")
    hir_mod.register_class_parent("MacroArrayValue", "MacroValue")
    hash_ref = macro_hash_type(
      hir_mod,
      "Hash(String, MacroValue)",
      Adamas::HIR::TypeRef::POINTER
    )
    union_ref = macro_nullable_union(
      hir_mod,
      "Nil | Hash(String, MacroValue)",
      hash_ref
    )
    parent = hir_mod.create_function(
      "MacroValue#call_method$String_Array(MacroValue)_Nil",
      Adamas::HIR::TypeRef::POINTER
    )
    child = hir_mod.create_function(
      "MacroArrayValue#call_method$String_Array(MacroValue)_Nil|Hash(String,MacroValue)",
      Adamas::HIR::TypeRef::POINTER
    )
    parent_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Class, "MacroValue"))
    child_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Class, "MacroArrayValue"))
    add_macro_method_params(parent, Adamas::HIR::TypeRef::NIL, parent_ref)
    add_macro_method_params(child, union_ref, child_ref)

    lowering = Adamas::MIR::HIRToMIRLowering.new(hir_mod)
    lowering.register_union_types([
      macro_nullable_union_registration(
        union_ref,
        "Nil | Hash(String, MacroValue)",
        hash_ref
      ),
    ])
    lowering.prepare

    resolved = lowering.__test_macro_nullable_virtual_resolution(
      "MacroArrayValue",
      "call_method$String_Array(MacroValue)_Nil",
      3
    )
    resolved.should_not be_nil
    resolved.not_nil!.name.should eq(child.name)
  end

  it "retains an exact inherited target for a child without a compatible union parameter" do
    hir_mod = Adamas::HIR::Module.new("macro_nonnullable_virtual_override")
    hir_mod.register_class_parent("MacroArrayValue", "MacroValue")
    parent = hir_mod.create_function(
      "MacroValue#call_method$String_Array(MacroValue)_Nil",
      Adamas::HIR::TypeRef::POINTER
    )
    child = hir_mod.create_function(
      "MacroArrayValue#call_method$String_Array(MacroValue)_String",
      Adamas::HIR::TypeRef::POINTER
    )
    add_macro_method_params(parent, Adamas::HIR::TypeRef::NIL)
    add_macro_method_params(child, Adamas::HIR::TypeRef::STRING)

    lowering = Adamas::MIR::HIRToMIRLowering.new(hir_mod)
    lowering.prepare
    resolved = lowering.__test_macro_nullable_virtual_resolution(
      "MacroArrayValue",
      "call_method$String_Array(MacroValue)_Nil",
      3
    )
    resolved.should_not be_nil
    resolved.not_nil!.name.should eq(parent.name)
  end

  it "preserves an inherited Char overload when the child family only has String" do
    hir_mod = Adamas::HIR::Module.new("inherited_char_overload")
    hir_mod.register_class_parent("Child", "Base")
    parent = hir_mod.create_function(
      "Base#print$Char",
      Adamas::HIR::TypeRef::POINTER
    )
    child = hir_mod.create_function(
      "Child#print$String",
      Adamas::HIR::TypeRef::POINTER
    )
    parent.add_param("self", Adamas::HIR::TypeRef::POINTER)
    parent.add_param("value", Adamas::HIR::TypeRef::CHAR)
    child.add_param("self", Adamas::HIR::TypeRef::POINTER)
    child.add_param("value", Adamas::HIR::TypeRef::STRING)

    lowering = Adamas::MIR::HIRToMIRLowering.new(hir_mod)
    lowering.prepare
    resolved = lowering.__test_macro_nullable_virtual_resolution("Child", "print$Char", 1)
    resolved.should_not be_nil
    resolved.not_nil!.name.should eq(parent.name)
  end

  it "does not choose arbitrarily when two child union families are compatible" do
    hir_mod = Adamas::HIR::Module.new("ambiguous_nullable_virtual_override")
    hir_mod.register_class_parent("MacroArrayValue", "MacroValue")
    first_hash_ref = macro_hash_type(
      hir_mod,
      "Hash(String, MacroValue)",
      Adamas::HIR::TypeRef::POINTER
    )
    second_hash_ref = macro_hash_type(
      hir_mod,
      "Hash(String, String)",
      Adamas::HIR::TypeRef::STRING
    )
    first_union = macro_nullable_union(
      hir_mod,
      "Nil | Hash(String, MacroValue)",
      first_hash_ref
    )
    second_union = macro_nullable_union(
      hir_mod,
      "Nil | Hash(String, String)",
      second_hash_ref
    )
    parent = hir_mod.create_function(
      "MacroValue#call_method$String_Array(MacroValue)_Nil",
      Adamas::HIR::TypeRef::POINTER
    )
    child_hash = hir_mod.create_function(
      "MacroArrayValue#call_method$String_Array(MacroValue)_Nil|Hash(String,MacroValue)",
      Adamas::HIR::TypeRef::POINTER
    )
    child_string = hir_mod.create_function(
      "MacroArrayValue#call_method$String_Array(MacroValue)_Nil|Hash(String,String)",
      Adamas::HIR::TypeRef::POINTER
    )
    add_macro_method_params(parent, Adamas::HIR::TypeRef::NIL)
    add_macro_method_params(child_hash, first_union)
    add_macro_method_params(child_string, second_union)
    arity_alias = hir_mod.create_function("MacroArrayValue#call_method$arity3", Adamas::HIR::TypeRef::POINTER)
    add_macro_method_params(arity_alias, first_union)

    lowering = Adamas::MIR::HIRToMIRLowering.new(hir_mod)
    lowering.register_union_types([
      macro_nullable_union_registration(
        first_union,
        "Nil | Hash(String, MacroValue)",
        first_hash_ref
      ),
      macro_nullable_union_registration(
        second_union,
        "Nil | Hash(String, String)",
        second_hash_ref
      ),
    ])
    lowering.prepare

    resolved = lowering.__test_macro_nullable_virtual_resolution(
      "MacroArrayValue",
      "call_method$String_Array(MacroValue)_Nil",
      3
    )
    resolved.should_not be_nil
    resolved.not_nil!.name.should eq(parent.name)
  end

  {"non_nil_argument", "other_parameter", "return_type"}.each do |conflict|
    it "retains the inherited target on #{conflict} conflict despite a nullable child" do
      hir_mod = Adamas::HIR::Module.new(conflict)
      hir_mod.register_class_parent("Child", "Base")
      union_ref = macro_nullable_union(hir_mod, "Nil | String", Adamas::HIR::TypeRef::STRING)
      parent = hir_mod.create_function("Base#read$exact", Adamas::HIR::TypeRef::POINTER)
      child = hir_mod.create_function("Child#read$nullable", conflict == "return_type" ? Adamas::HIR::TypeRef::INT32 : Adamas::HIR::TypeRef::POINTER)
      parent.add_param("self", Adamas::HIR::TypeRef::POINTER)
      child.add_param("self", Adamas::HIR::TypeRef::POINTER)
      parent.add_param("name", Adamas::HIR::TypeRef::STRING)
      child.add_param("name", conflict == "other_parameter" ? Adamas::HIR::TypeRef::INT32 : Adamas::HIR::TypeRef::STRING)
      parent.add_param("value", conflict == "non_nil_argument" ? Adamas::HIR::TypeRef::INT32 : Adamas::HIR::TypeRef::NIL)
      child.add_param("value", union_ref)
      lowering = Adamas::MIR::HIRToMIRLowering.new(hir_mod)
      lowering.register_union_types([macro_nullable_union_registration(union_ref, "Nil | String", Adamas::HIR::TypeRef::STRING)])
      lowering.prepare
      resolved = lowering.__test_macro_nullable_virtual_resolution("Child", "read$exact", 2)
      resolved.should_not be_nil
      resolved.not_nil!.name.should eq(parent.name)
    end
  end

end
