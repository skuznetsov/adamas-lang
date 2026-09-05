require "../spec_helper"
require "../../src/compiler/hir/hir"

describe "HIR type descriptor lookup" do
  it "returns the descriptor stored for a user type" do
    hir_module = Adamas::HIR::Module.new("descriptor_lookup")
    descriptor = Adamas::HIR::TypeDescriptor.new(
      Adamas::HIR::TypeKind::Union,
      "Int32 | Int64",
      [Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::INT64],
    )
    type_ref = hir_module.intern_type(descriptor)

    type_ref.id.should eq(Adamas::HIR::TypeRef::FIRST_USER_TYPE)
    hir_module.get_type_descriptor(type_ref).should eq(descriptor)

    second = Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Class, "Second")
    second_ref = hir_module.intern_type(second)
    hir_module.get_type_descriptor(second_ref).should eq(second)
    hir_module.get_type_descriptor(type_ref).should eq(descriptor)
  end

  it "returns nil for primitive and out-of-range references" do
    hir_module = Adamas::HIR::Module.new("descriptor_lookup_bounds")
    type_ref = hir_module.intern_type(
      Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Class, "Present")
    )

    hir_module.get_type_descriptor(Adamas::HIR::TypeRef::INT32).should be_nil
    hir_module.get_type_descriptor(
      Adamas::HIR::TypeRef.new(Adamas::HIR::TypeRef::FIRST_USER_TYPE - 1_u32)
    ).should be_nil
    hir_module.get_type_descriptor(
      Adamas::HIR::TypeRef.new(type_ref.id + 1_u32)
    ).should be_nil
  end
end
