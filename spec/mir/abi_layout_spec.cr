require "../spec_helper"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/mir/hir_to_mir"
require "../../src/compiler/mir/llvm_backend"

# Parse Crystal code and return arena + roots
private def parse(code : String) : {Adamas::Compiler::Frontend::ArenaLike, Array(Adamas::Compiler::Frontend::ExprId)}
  lexer = Adamas::Compiler::Frontend::Lexer.new(code)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  {result.arena, result.roots}
end

# Build MIR module with registered class/struct/union layouts (no function lowering).
private def build_mir_module(code : String) : Adamas::MIR::Module
  arena, exprs = parse(code)
  converter = Adamas::HIR::AstToHir.new(arena)

  class_nodes = [] of Adamas::Compiler::Frontend::ClassNode
  enum_nodes = [] of Adamas::Compiler::Frontend::EnumNode

  exprs.each do |expr_id|
    node = arena[expr_id]
    case node
    when Adamas::Compiler::Frontend::ClassNode
      class_nodes << node
    when Adamas::Compiler::Frontend::EnumNode
      enum_nodes << node
    end
  end

  enum_nodes.each { |n| converter.register_enum(n) }
  class_nodes.each { |n| converter.register_class(n) }

  mir_lowering = Adamas::MIR::HIRToMIRLowering.new(converter.module)
  mir_lowering.register_union_types(converter.union_descriptor_entries)
  mir_lowering.register_class_types(converter.class_info)
  mir_lowering.mir_module
end

private def union_variant(
  type_ref : Adamas::MIR::TypeRef,
  name : String,
  size : Int32 = 8,
  alignment : Int32 = 8,
) : Adamas::MIR::UnionVariantDescriptor
  Adamas::MIR::UnionVariantDescriptor.new(
    type_id: type_ref == Adamas::MIR::TypeRef::NIL ? 0 : type_ref.id.to_i32,
    type_ref: type_ref,
    full_name: name,
    size: type_ref == Adamas::MIR::TypeRef::NIL ? 0 : size,
    alignment: type_ref == Adamas::MIR::TypeRef::NIL ? 1 : alignment,
    field_offsets: nil
  )
end

private def register_layout_union(
  lowering : Adamas::MIR::HIRToMIRLowering,
  type_ref : Adamas::MIR::TypeRef,
  name : String,
  variants : Array(Adamas::MIR::UnionVariantDescriptor),
) : Nil
  descriptor = Adamas::MIR::UnionDescriptor.new(name, variants, 16, 8)
  lowering.register_union_types([
    Adamas::HIR::UnionDescriptorRegistration.new(type_ref, descriptor),
  ])
end

describe "MIR ABI layout sanity" do
  it "lays out class ivars with a header offset" do
    code = <<-CRYSTAL
      class A
        @x : Int32
        @y : Int64
      end
    CRYSTAL

    mir_mod = build_mir_module(code)
    a_type = mir_mod.type_registry.get_by_name("A").not_nil!

    a_type.kind.reference?.should be_true
    # 4-byte type_id header + Int32(4) + Int64(8) = 16, aligned to 8
    a_type.size.should eq(16)
    a_type.alignment.should eq(8)

    fields = a_type.fields.not_nil!
    fields.find(&.name.==("@x")).not_nil!.offset.should eq(4)
    fields.find(&.name.==("@y")).not_nil!.offset.should eq(8)
  end

  it "lays out subclass ivars after parent fields" do
    code = <<-CRYSTAL
      class Parent
        @x : Int32
      end

      class Child < Parent
        @y : Int64
      end
    CRYSTAL

    mir_mod = build_mir_module(code)
    child_type = mir_mod.type_registry.get_by_name("Child").not_nil!

    child_type.kind.reference?.should be_true
    # 4-byte type_id header + Int32(4) + Int64(8) = 16, aligned to 8
    child_type.size.should eq(16)
    child_type.alignment.should eq(8)

    fields = child_type.fields.not_nil!
    fields.find(&.name.==("@x")).not_nil!.offset.should eq(4)
    fields.find(&.name.==("@y")).not_nil!.offset.should eq(8)
  end

  it "lays out struct ivars without a header offset" do
    code = <<-CRYSTAL
      struct S
        @a : Int32
        @b : Int64
      end
    CRYSTAL

    mir_mod = build_mir_module(code)
    s_type = mir_mod.type_registry.get_by_name("S").not_nil!

    s_type.kind.struct?.should be_true
    # Struct has no header. @a:Int32@0(4) + 4 padding + @b:Int64@8(8) = 16
    s_type.size.should eq(16)
    s_type.alignment.should eq(8)

    fields = s_type.fields.not_nil!
    fields.find(&.name.==("@a")).not_nil!.offset.should eq(0)
    fields.find(&.name.==("@b")).not_nil!.offset.should eq(8)
  end

  it "uses pointer-sized alignment for reference ivars" do
    code = <<-CRYSTAL
      class RefHolder
        @s : String
      end
    CRYSTAL

    mir_mod = build_mir_module(code)
    t = mir_mod.type_registry.get_by_name("RefHolder").not_nil!

    expected_ptr_align = {% if flag?(:i386) || flag?(:arm) %}4{% else %}8{% end %}
    expected_size = {% if flag?(:i386) || flag?(:arm) %}8{% else %}16{% end %}
    expected_offset = {% if flag?(:i386) || flag?(:arm) %}4{% else %}8{% end %}

    t.kind.reference?.should be_true
    t.alignment.should eq(expected_ptr_align)
    t.size.should eq(expected_size)
    t.fields.not_nil!.find(&.name.==("@s")).not_nil!.offset.should eq(expected_offset)
  end

  it "computes union header and payload offsets" do
    code = <<-CRYSTAL
      class U
        @u : Int32 | Int64
      end
    CRYSTAL

    mir_mod = build_mir_module(code)
    union_type = mir_mod.type_registry.get_by_name("Int32 | Int64").not_nil!
    union_type.kind.union?.should be_true
    union_type.size.should eq(16)
    union_type.alignment.should eq(8)

    descriptor = mir_mod.get_union_descriptor(Adamas::MIR::TypeRef.new(union_type.id)).not_nil!
    descriptor.payload_offset.should eq(8)
    descriptor.max_payload_size.should eq(8)
  end

  it "aligns union payload to the max variant alignment" do
    code = <<-CRYSTAL
      class U
        @u : Int128 | Int8
      end
    CRYSTAL

    mir_mod = build_mir_module(code)
    union_type = mir_mod.type_registry.get_by_name("Int128 | Int8").not_nil!
    union_type.kind.union?.should be_true
    union_type.size.should eq(32)
    union_type.alignment.should eq(16)

    descriptor = mir_mod.get_union_descriptor(Adamas::MIR::TypeRef.new(union_type.id)).not_nil!
    descriptor.payload_offset.should eq(16)
    descriptor.max_payload_size.should eq(16)
  end

  it "keeps HIR union layout and LLVM carrier on one authoritative storage contract" do
    lowering = Adamas::MIR::HIRToMIRLowering.new(Adamas::HIR::Module.new("union_storage_contract"))
    mir_mod = lowering.mir_module
    registry = mir_mod.type_registry

    header_a_ref = Adamas::MIR::TypeRef.new(400_u32)
    header_b_ref = Adamas::MIR::TypeRef.new(401_u32)
    ptr_i32_ref = Adamas::MIR::TypeRef.new(402_u32)
    ptr_u8_ref = Adamas::MIR::TypeRef.new(403_u32)
    tuple_ref = Adamas::MIR::TypeRef.new(404_u32)
    registry.create_type_with_id(header_a_ref.id, Adamas::MIR::TypeKind::Reference, "HeaderA", 8, 8)
    registry.create_type_with_id(header_b_ref.id, Adamas::MIR::TypeKind::Reference, "HeaderB", 8, 8)
    registry.create_type_with_id(ptr_i32_ref.id, Adamas::MIR::TypeKind::Pointer, "Pointer(Int32)", 8, 8)
    registry.create_type_with_id(ptr_u8_ref.id, Adamas::MIR::TypeKind::Pointer, "Pointer(UInt8)", 8, 8)
    registry.create_type_with_id(tuple_ref.id, Adamas::MIR::TypeKind::Tuple, "Tuple(Int32, Int32)", 8, 4)

    header_union_ref = Adamas::MIR::TypeRef.new(500_u32)
    nullable_ptr_ref = Adamas::MIR::TypeRef.new(501_u32)
    distinct_ptr_ref = Adamas::MIR::TypeRef.new(502_u32)
    mixed_ptr_ref = Adamas::MIR::TypeRef.new(503_u32)
    tuple_union_ref = Adamas::MIR::TypeRef.new(504_u32)
    scalar_union_ref = Adamas::MIR::TypeRef.new(505_u32)
    ptr_nil_void_ref = Adamas::MIR::TypeRef.new(506_u32)
    duplicate_ptr_ref = Adamas::MIR::TypeRef.new(507_u32)

    register_layout_union(lowering, header_union_ref, "HeaderA | HeaderB | Nil", [
      union_variant(header_a_ref, "HeaderA"),
      union_variant(header_b_ref, "HeaderB"),
      union_variant(Adamas::MIR::TypeRef::NIL, "Nil"),
    ])
    register_layout_union(lowering, nullable_ptr_ref, "Pointer(Int32) | Nil", [
      union_variant(ptr_i32_ref, "Pointer(Int32)"),
      union_variant(Adamas::MIR::TypeRef::NIL, "Nil"),
    ])
    register_layout_union(lowering, distinct_ptr_ref, "Pointer(Int32) | Pointer(UInt8)", [
      union_variant(ptr_i32_ref, "Pointer(Int32)"),
      union_variant(ptr_u8_ref, "Pointer(UInt8)"),
    ])
    register_layout_union(lowering, mixed_ptr_ref, "Pointer(Int32) | HeaderA | Nil", [
      union_variant(ptr_i32_ref, "Pointer(Int32)"),
      union_variant(header_a_ref, "HeaderA"),
      union_variant(Adamas::MIR::TypeRef::NIL, "Nil"),
    ])
    register_layout_union(lowering, tuple_union_ref, "Tuple(Int32, Int32) | Nil", [
      union_variant(tuple_ref, "Tuple(Int32, Int32)", 8, 4),
      union_variant(Adamas::MIR::TypeRef::NIL, "Nil"),
    ])
    register_layout_union(lowering, scalar_union_ref, "Int32 | Nil", [
      union_variant(Adamas::MIR::TypeRef::INT32, "Int32", 4, 4),
      union_variant(Adamas::MIR::TypeRef::NIL, "Nil"),
    ])
    register_layout_union(lowering, ptr_nil_void_ref, "Pointer(Int32) | Nil | Void", [
      union_variant(ptr_i32_ref, "Pointer(Int32)"),
      union_variant(Adamas::MIR::TypeRef::NIL, "Nil"),
      union_variant(Adamas::MIR::TypeRef::VOID, "Void", 0, 1),
    ])
    register_layout_union(lowering, duplicate_ptr_ref, "Pointer(Int32) | Pointer(Int32) | Nil", [
      union_variant(ptr_i32_ref, "Pointer(Int32)"),
      union_variant(ptr_i32_ref, "Pointer(Int32)"),
      union_variant(Adamas::MIR::TypeRef::NIL, "Nil"),
    ])
    mir_mod.refresh_union_storage_kinds

    mapper = Adamas::MIR::LLVMTypeMapper.new(registry)
    mapper.union_descriptor_entries = mir_mod.union_descriptor_entries
    mapper.union_storage_entries = mir_mod.union_storage_entries

    mir_mod.get_union_storage_kind(header_union_ref).should eq(Adamas::MIR::UnionStorageKind::RawHeaderPointer)
    mir_mod.get_union_storage_kind(nullable_ptr_ref).should eq(Adamas::MIR::UnionStorageKind::RawNullablePointer)
    mir_mod.get_union_storage_kind(distinct_ptr_ref).should eq(Adamas::MIR::UnionStorageKind::Tagged)
    mir_mod.get_union_storage_kind(mixed_ptr_ref).should eq(Adamas::MIR::UnionStorageKind::Tagged)
    mir_mod.get_union_storage_kind(tuple_union_ref).should eq(Adamas::MIR::UnionStorageKind::Tagged)
    mir_mod.get_union_storage_kind(scalar_union_ref).should eq(Adamas::MIR::UnionStorageKind::Tagged)
    mir_mod.get_union_storage_kind(ptr_nil_void_ref).should eq(Adamas::MIR::UnionStorageKind::RawNullablePointer)
    mir_mod.get_union_storage_kind(duplicate_ptr_ref).should eq(Adamas::MIR::UnionStorageKind::Tagged)

    {header_union_ref, nullable_ptr_ref, ptr_nil_void_ref}.each do |type_ref|
      type = registry.get(type_ref).not_nil!
      type.size.should eq(Adamas::MIR::TARGET_POINTER_BYTES_U64)
      type.alignment.should eq(Adamas::MIR::TARGET_POINTER_ALIGN_U32)
      mapper.llvm_type(type_ref).should eq("ptr")
    end
    {distinct_ptr_ref, mixed_ptr_ref, tuple_union_ref, scalar_union_ref, duplicate_ptr_ref}.each do |type_ref|
      type = registry.get(type_ref).not_nil!
      type.size.should eq(16)
      type.alignment.should eq(8)
      mapper.llvm_type(type_ref).should match(/\.union$/)
    end

    unknown = Adamas::MIR::UnionDescriptor.new(
      "Unknown | Nil",
      [
        union_variant(Adamas::MIR::TypeRef.new(999_u32), "Unknown"),
        union_variant(Adamas::MIR::TypeRef::NIL, "Nil"),
      ],
      16,
      8
    )
    Adamas::MIR.union_storage_kind(registry, unknown).should eq(Adamas::MIR::UnionStorageKind::Tagged)
  end
end
