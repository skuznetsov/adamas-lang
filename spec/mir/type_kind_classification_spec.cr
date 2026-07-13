require "../spec_helper"
require "../../src/compiler/mir/mir"

private def classified_mir_type(kind : Adamas::MIR::TypeKind, name : String) : Adamas::MIR::Type
  Adamas::MIR::Type.new(100_u32, kind, name, 8_u64, 8_u32)
end

describe "MIR type-kind classification" do
  it "recognizes only reference and array types as runtime-header-backed" do
    Adamas::MIR.runtime_header_backed_type?(classified_mir_type(Adamas::MIR::TypeKind::Reference, "Object")).should be_true
    Adamas::MIR.runtime_header_backed_type?(classified_mir_type(Adamas::MIR::TypeKind::Array, "Array(Int32)")).should be_true
    Adamas::MIR.runtime_header_backed_type?(classified_mir_type(Adamas::MIR::TypeKind::Pointer, "Pointer(Int32)")).should be_false
    Adamas::MIR.runtime_header_backed_type?(nil).should be_false
  end

  it "recognizes raw pointer variants by registered kind or canonical name" do
    pointer = classified_mir_type(Adamas::MIR::TypeKind::Pointer, "OpaquePointerAlias")
    struct_type = classified_mir_type(Adamas::MIR::TypeKind::Struct, "PointerLike")

    Adamas::MIR.raw_pointer_union_variant?(pointer, pointer.name).should be_true
    Adamas::MIR.raw_pointer_union_variant?(nil, "Pointer").should be_true
    Adamas::MIR.raw_pointer_union_variant?(nil, "Pointer(UInt8)").should be_true
    Adamas::MIR.raw_pointer_union_variant?(struct_type, struct_type.name).should be_false
    Adamas::MIR.raw_pointer_union_variant?(nil, "PointerThing").should be_false
  end
end
