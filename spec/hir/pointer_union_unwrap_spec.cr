require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/mir/mir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

# Test-only access to the narrow pointer-union helper.  Keeping the probe at the
# HIR boundary makes the representation decision observable without compiling a
# whole stdlib slice.
class Adamas::HIR::AstToHir
  def __test_type_ref_for_pointer_union(name : String) : Adamas::HIR::TypeRef
    type_ref_for_name(name)
  end

  def __test_replace_union_descriptor(
    union_type : Adamas::HIR::TypeRef,
    descriptor : Adamas::MIR::UnionDescriptor,
  ) : Nil
    mir_ref = Adamas::MIR::TypeRef.from_hir(union_type)
    @union_descriptors[mir_ref] = descriptor
    entries = @union_descriptor_entries
    entry_idx = 0
    replaced = false
    while entry_idx < entries.size
      if entries.unsafe_fetch(entry_idx).type_ref == mir_ref
        entries[entry_idx] = Adamas::HIR::UnionDescriptorRegistration.new(mir_ref, descriptor)
        replaced = true
        break
      end
      entry_idx += 1
    end
    entries << Adamas::HIR::UnionDescriptorRegistration.new(mir_ref, descriptor) unless replaced
  end

  def __test_replace_union_descriptor_hash_only(
    union_type : Adamas::HIR::TypeRef,
    descriptor : Adamas::MIR::UnionDescriptor,
  ) : Nil
    @union_descriptors[Adamas::MIR::TypeRef.from_hir(union_type)] = descriptor
  end

  def __test_append_union_descriptor_sidecar(
    union_type : Adamas::HIR::TypeRef,
    descriptor : Adamas::MIR::UnionDescriptor,
  ) : Nil
    mir_ref = Adamas::MIR::TypeRef.from_hir(union_type)
    @union_descriptor_entries << Adamas::HIR::UnionDescriptorRegistration.new(mir_ref, descriptor)
  end

  def __test_unwrap_pointer_union(
    receiver_type : Adamas::HIR::TypeRef,
    value_type : Adamas::HIR::TypeRef?,
    allow_void_fallback : Bool = false,
  ) : Adamas::HIR::UnionUnwrap?
    function = @module.create_function("__pointer_union_probe", receiver_type)
    receiver = function.add_param("receiver", receiver_type)
    context = Adamas::HIR::LoweringContext.new(function, @module, @arena)
    context.register_type(receiver.id, receiver_type)
    lowered = unwrap_pointer_union(context, receiver.id, receiver_type, value_type, allow_void_fallback)
    lowered ? context.value_for(lowered[0]).as(Adamas::HIR::UnionUnwrap) : nil
  end

  def __test_lower_primitive_pointer_set(
    receiver_type : Adamas::HIR::TypeRef,
    value_type : Adamas::HIR::TypeRef,
  ) : Adamas::HIR::Function
    function = @module.create_function("__pointer_union_primitive_set_probe", Adamas::HIR::TypeRef::VOID)
    receiver = function.add_param("receiver", receiver_type)
    value = function.add_param("value", value_type)
    context = Adamas::HIR::LoweringContext.new(function, @module, @arena)
    context.register_type(receiver.id, receiver_type)
    context.register_type(value.id, value_type)
    lower_primitive_pointer_set(context, receiver.id, [value.id], "Pointer(#{type_name_for_ref(receiver_type)})#value=")
    function
  end

  private def type_name_for_ref(type_ref : Adamas::HIR::TypeRef) : String
    @module.get_type_descriptor(type_ref).try(&.name) || "Pointer"
  end

end

private def pointer_union_converter : Adamas::HIR::AstToHir
  lexer = Adamas::Compiler::Frontend::Lexer.new("")
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  converter = Adamas::HIR::AstToHir.new(result.arena)
  converter.arena = result.arena
  converter
end

private def lower_pointer_union_store_source : {Adamas::HIR::Function, Adamas::HIR::AstToHir}
  source = <<-CRYSTAL
    def pointer_union_store(pointer : Pointer(UInt8) | Pointer(Void), value : Int32)
      pointer.value = value
    end
  CRYSTAL
  lexer = Adamas::Compiler::Frontend::Lexer.new(source)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  converter = Adamas::HIR::AstToHir.new(result.arena)
  def_expr = result.roots.find { |expr_id| result.arena[expr_id].is_a?(Adamas::Compiler::Frontend::DefNode) }
  raise "missing pointer union def" unless def_expr
  function = converter.lower_def(result.arena[def_expr.not_nil!].as(Adamas::Compiler::Frontend::DefNode))
  {function, converter}
end

private def lower_pointer_union_load_source : {Adamas::HIR::Function, Adamas::HIR::AstToHir}
  source = <<-CRYSTAL
    def pointer_union_load(pointer : Pointer(UInt8) | Pointer(Void)) : UInt8
      pointer.value
    end
  CRYSTAL
  lexer = Adamas::Compiler::Frontend::Lexer.new(source)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  converter = Adamas::HIR::AstToHir.new(result.arena)
  def_expr = result.roots.find { |expr_id| result.arena[expr_id].is_a?(Adamas::Compiler::Frontend::DefNode) }
  raise "missing pointer union load def" unless def_expr
  function = converter.lower_def(result.arena[def_expr.not_nil!].as(Adamas::Compiler::Frontend::DefNode))
  {function, converter}
end

private def lower_pointer_union_index_store_source : {Adamas::HIR::Function, Adamas::HIR::AstToHir}
  source = <<-CRYSTAL
    def pointer_union_index_store(pointer : Pointer(UInt8) | Pointer(Void), index : Int32, value : Int32)
      pointer[index] = value
    end
  CRYSTAL
  lexer = Adamas::Compiler::Frontend::Lexer.new(source)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  converter = Adamas::HIR::AstToHir.new(result.arena)
  def_expr = result.roots.find { |expr_id| result.arena[expr_id].is_a?(Adamas::Compiler::Frontend::DefNode) }
  raise "missing pointer union indexed-store def" unless def_expr
  function = converter.lower_def(result.arena[def_expr.not_nil!].as(Adamas::Compiler::Frontend::DefNode))
  {function, converter}
end

private def lower_pointer_union_add_source : {Adamas::HIR::Function, Adamas::HIR::AstToHir}
  source = <<-CRYSTAL
    def pointer_union_add(pointer : Pointer(UInt8) | Pointer(Void), offset : Int32) : Pointer(UInt8)
      pointer + offset
    end
  CRYSTAL
  lexer = Adamas::Compiler::Frontend::Lexer.new(source)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  converter = Adamas::HIR::AstToHir.new(result.arena)
  def_expr = result.roots.find { |expr_id| result.arena[expr_id].is_a?(Adamas::Compiler::Frontend::DefNode) }
  raise "missing pointer union add def" unless def_expr
  function = converter.lower_def(result.arena[def_expr.not_nil!].as(Adamas::Compiler::Frontend::DefNode))
  {function, converter}
end

private def lower_mixed_pointer_store_source : Adamas::HIR::Function
  source = <<-CRYSTAL
    class Widget
    end

    def mixed_pointer_store(pointer : Pointer(UInt8) | Widget, value : Int32)
      pointer.value = value
    end
  CRYSTAL
  lexer = Adamas::Compiler::Frontend::Lexer.new(source)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  converter = Adamas::HIR::AstToHir.new(result.arena)
  class_expr = result.roots.find { |expr_id| result.arena[expr_id].is_a?(Adamas::Compiler::Frontend::ClassNode) }
  converter.register_class(result.arena[class_expr.not_nil!].as(Adamas::Compiler::Frontend::ClassNode)) if class_expr
  def_expr = result.roots.find { |expr_id| result.arena[expr_id].is_a?(Adamas::Compiler::Frontend::DefNode) }
  raise "missing mixed pointer-store def" unless def_expr
  converter.lower_def(result.arena[def_expr.not_nil!].as(Adamas::Compiler::Frontend::DefNode))
end

private def lower_pointer_union_set_type_id_source : {Adamas::HIR::Function, Adamas::HIR::AstToHir}
  source = <<-CRYSTAL
    class PointerUnionTypeIdProbe
      def self.write_type_id(pointer : Pointer(UInt8) | Pointer(Void))
        set_crystal_type_id(pointer)
      end
    end
  CRYSTAL
  lexer = Adamas::Compiler::Frontend::Lexer.new(source)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  converter = Adamas::HIR::AstToHir.new(result.arena)
  converter.arena = result.arena
  class_expr = result.roots.find { |expr_id| result.arena[expr_id].is_a?(Adamas::Compiler::Frontend::ClassNode) }
  raise "missing pointer-union type-id probe class" unless class_expr
  class_node = result.arena[class_expr.not_nil!].as(Adamas::Compiler::Frontend::ClassNode)
  converter.register_class(class_node)
  converter.lower_class(class_node)
  function = converter.module.functions.find do |candidate|
    candidate.name.starts_with?("PointerUnionTypeIdProbe.write_type_id")
  end
  raise "missing pointer-union type-id probe function" unless function
  {function.not_nil!, converter}
end

private def lower_pointer_union_qualified_set_type_id_source : {Adamas::HIR::Function, Adamas::HIR::AstToHir}
  source = <<-CRYSTAL
    class PointerUnionQualifiedTypeIdProbe
    end

    def pointer_union_qualified_type_id(pointer : Pointer(UInt8) | Pointer(Void))
      PointerUnionQualifiedTypeIdProbe.set_crystal_type_id(pointer)
    end
  CRYSTAL
  lexer = Adamas::Compiler::Frontend::Lexer.new(source)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  converter = Adamas::HIR::AstToHir.new(result.arena)
  converter.arena = result.arena
  class_expr = result.roots.find { |expr_id| result.arena[expr_id].is_a?(Adamas::Compiler::Frontend::ClassNode) }
  raise "missing qualified pointer-union type-id probe class" unless class_expr
  converter.register_class(result.arena[class_expr.not_nil!].as(Adamas::Compiler::Frontend::ClassNode))
  def_expr = result.roots.find { |expr_id| result.arena[expr_id].is_a?(Adamas::Compiler::Frontend::DefNode) }
  raise "missing qualified pointer-union type-id probe function" unless def_expr
  function = converter.lower_def(result.arena[def_expr.not_nil!].as(Adamas::Compiler::Frontend::DefNode))
  {function, converter}
end

private def lower_pointer_union_fallback_set_type_id_source : {Adamas::HIR::Function, Adamas::HIR::AstToHir}
  source = <<-CRYSTAL
    def set_crystal_type_id(pointer : Pointer(Void), ignored : Int32 = 0)
      pointer
    end

    class PointerUnionFallbackTypeIdProbe
      def self.write_type_id(pointer : Pointer(UInt8) | Pointer(Void))
        set_crystal_type_id(pointer, ignored: 0)
      end
    end
  CRYSTAL
  lexer = Adamas::Compiler::Frontend::Lexer.new(source)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  converter = Adamas::HIR::AstToHir.new(result.arena)
  converter.arena = result.arena
  class_expr = result.roots.find { |expr_id| result.arena[expr_id].is_a?(Adamas::Compiler::Frontend::ClassNode) }
  raise "missing fallback pointer-union type-id probe class" unless class_expr
  class_node = result.arena[class_expr.not_nil!].as(Adamas::Compiler::Frontend::ClassNode)
  converter.register_class(class_node)
  top_level_def_expr = result.roots.find { |expr_id| result.arena[expr_id].is_a?(Adamas::Compiler::Frontend::DefNode) }
  converter.register_function(result.arena[top_level_def_expr.not_nil!].as(Adamas::Compiler::Frontend::DefNode)) if top_level_def_expr
  converter.lower_class(class_node)
  function = converter.module.functions.find do |candidate|
    candidate.name.starts_with?("PointerUnionFallbackTypeIdProbe.write_type_id")
  end
  raise "missing fallback pointer-union type-id probe function" unless function
  {function.not_nil!, converter}
end

private def lower_mixed_pointer_union_set_type_id_source : Adamas::HIR::Function
  source = <<-CRYSTAL
    class PointerUnionMixedTypeIdWidget
    end

    class PointerUnionMixedTypeIdProbe
      def self.write_type_id(pointer : Pointer(UInt8) | PointerUnionMixedTypeIdWidget)
        set_crystal_type_id(pointer)
      end
    end
  CRYSTAL
  lexer = Adamas::Compiler::Frontend::Lexer.new(source)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  converter = Adamas::HIR::AstToHir.new(result.arena)
  converter.arena = result.arena
  result.roots.each do |expr_id|
    node = result.arena[expr_id]
    converter.register_class(node.as(Adamas::Compiler::Frontend::ClassNode)) if node.is_a?(Adamas::Compiler::Frontend::ClassNode)
    converter.register_function(node.as(Adamas::Compiler::Frontend::DefNode)) if node.is_a?(Adamas::Compiler::Frontend::DefNode)
  end
  probe_expr = result.roots.find do |expr_id|
    node = result.arena[expr_id]
    node.is_a?(Adamas::Compiler::Frontend::ClassNode) &&
      String.new(node.as(Adamas::Compiler::Frontend::ClassNode).name) == "PointerUnionMixedTypeIdProbe"
  end
  raise "missing mixed pointer-union type-id probe class" unless probe_expr
  converter.lower_class(result.arena[probe_expr.not_nil!].as(Adamas::Compiler::Frontend::ClassNode))
  function = converter.module.functions.find do |candidate|
    candidate.name.starts_with?("PointerUnionMixedTypeIdProbe.write_type_id")
  end
  raise "missing mixed pointer-union type-id probe function" unless function
  function.not_nil!
end

private def lower_mixed_pointer_union_fallback_set_type_id_source : Adamas::HIR::Function
  source = <<-CRYSTAL
    def set_crystal_type_id(pointer : Pointer(Void), ignored : Int32 = 0)
      pointer
    end

    class PointerUnionFallbackMixedTypeIdWidget
    end

    class PointerUnionFallbackMixedTypeIdProbe
      def self.write_type_id(pointer : Pointer(UInt8) | PointerUnionFallbackMixedTypeIdWidget)
        set_crystal_type_id(pointer, ignored: 0)
      end
    end
  CRYSTAL
  lexer = Adamas::Compiler::Frontend::Lexer.new(source)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  converter = Adamas::HIR::AstToHir.new(result.arena)
  converter.arena = result.arena
  result.roots.each do |expr_id|
    node = result.arena[expr_id]
    converter.register_class(node.as(Adamas::Compiler::Frontend::ClassNode)) if node.is_a?(Adamas::Compiler::Frontend::ClassNode)
  end
  probe_expr = result.roots.find do |expr_id|
    node = result.arena[expr_id]
    node.is_a?(Adamas::Compiler::Frontend::ClassNode) &&
      String.new(node.as(Adamas::Compiler::Frontend::ClassNode).name) == "PointerUnionFallbackMixedTypeIdProbe"
  end
  raise "missing fallback mixed pointer-union type-id probe class" unless probe_expr
  converter.lower_class(result.arena[probe_expr.not_nil!].as(Adamas::Compiler::Frontend::ClassNode))
  function = converter.module.functions.find do |candidate|
    candidate.name.starts_with?("PointerUnionFallbackMixedTypeIdProbe.write_type_id")
  end
  raise "missing fallback mixed pointer-union type-id probe function" unless function
  function.not_nil!
end

private def pointer_union_descriptor(
  converter : Adamas::HIR::AstToHir,
  union_type : Adamas::HIR::TypeRef,
  variants : Array({Int32, Adamas::HIR::TypeRef, String}),
) : Adamas::MIR::UnionDescriptor
  Adamas::MIR::UnionDescriptor.new(
    converter.module.get_type_descriptor(union_type).not_nil!.name,
    variants.map do |type_id, hir_type, full_name|
      Adamas::MIR::UnionVariantDescriptor.new(
        type_id: type_id,
        type_ref: Adamas::MIR::TypeRef.from_hir(hir_type),
        full_name: full_name,
        size: 8,
        alignment: 8,
        field_offsets: nil
      )
    end,
    32,
    8
  )
end

describe "pointer-union HIR normalization" do
  it "uses the descriptor discriminator for an exact typed-pointer match" do
    converter = pointer_union_converter
    pointer_u8 = converter.__test_type_ref_for_pointer_union("Pointer(UInt8)")
    pointer_void = converter.__test_type_ref_for_pointer_union("Pointer(Void)")
    union_type = converter.__test_type_ref_for_pointer_union("Pointer(UInt8) | Pointer(Void)")
    descriptor = pointer_union_descriptor(converter, union_type, [
      {37, pointer_u8, "Pointer(UInt8)"},
      {91, pointer_void, "Pointer(Void)"},
    ])
    converter.__test_replace_union_descriptor(union_type, descriptor)

    unwrap = converter.__test_unwrap_pointer_union(union_type, Adamas::HIR::TypeRef::UINT8)
    unwrap.should_not be_nil
    unwrap = unwrap.not_nil!
    unwrap.type.should eq(pointer_u8)
    # This is deliberately not the positional index (0).
    unwrap.variant_type_id.should eq(37)
  end

  it "accepts a local discriminator of zero for exact and opaque fallback matches" do
    converter = pointer_union_converter
    pointer_u8 = converter.__test_type_ref_for_pointer_union("Pointer(UInt8)")
    pointer_void = converter.__test_type_ref_for_pointer_union("Pointer(Void)")
    union_type = converter.__test_type_ref_for_pointer_union("Pointer(UInt8) | Pointer(Void)")
    descriptor = pointer_union_descriptor(converter, union_type, [
      {0, pointer_u8, "Pointer(UInt8)"},
      {91, pointer_void, "Pointer(Void)"},
    ])
    converter.__test_replace_union_descriptor(union_type, descriptor)

    exact = converter.__test_unwrap_pointer_union(union_type, Adamas::HIR::TypeRef::UINT8)
    exact.should_not be_nil
    exact.not_nil!.variant_type_id.should eq(0)

    opaque = converter.__test_unwrap_pointer_union(union_type, Adamas::HIR::TypeRef::INT32, true)
    opaque.should_not be_nil
    opaque.not_nil!.variant_type_id.should eq(91)
  end

  it "falls back only to an explicit Pointer(Void) arm when the value type is opaque" do
    converter = pointer_union_converter
    pointer_u8 = converter.__test_type_ref_for_pointer_union("Pointer(UInt8)")
    pointer_void = converter.__test_type_ref_for_pointer_union("Pointer(Void)")
    union_type = converter.__test_type_ref_for_pointer_union("Pointer(UInt8) | Pointer(Void)")
    descriptor = pointer_union_descriptor(converter, union_type, [
      {37, pointer_u8, "Pointer(UInt8)"},
      {91, pointer_void, "Pointer(Void)"},
    ])
    converter.__test_replace_union_descriptor(union_type, descriptor)

    unwrap = converter.__test_unwrap_pointer_union(union_type, Adamas::HIR::TypeRef::INT32, true)
    unwrap.should_not be_nil
    unwrap = unwrap.not_nil!
    unwrap.type.should eq(pointer_void)
    unwrap.variant_type_id.should eq(91)
  end

  it "selects the sole concrete pointer arm for a load with no requested value type" do
    converter = pointer_union_converter
    pointer_u8 = converter.__test_type_ref_for_pointer_union("Pointer(UInt8)")
    pointer_void = converter.__test_type_ref_for_pointer_union("Pointer(Void)")
    union_type = converter.__test_type_ref_for_pointer_union("Pointer(UInt8) | Pointer(Void)")
    descriptor = pointer_union_descriptor(converter, union_type, [
      {37, pointer_u8, "Pointer(UInt8)"},
      {91, pointer_void, "Pointer(Void)"},
    ])
    converter.__test_replace_union_descriptor(union_type, descriptor)

    unwrap = converter.__test_unwrap_pointer_union(union_type, nil)
    unwrap.should_not be_nil
    unwrap = unwrap.not_nil!
    unwrap.type.should eq(pointer_u8)
    unwrap.variant_type_id.should eq(37)
  end

  it "fails closed for a Nil | Pointer(Void) load instead of producing a Void load" do
    converter = pointer_union_converter
    pointer_void = converter.__test_type_ref_for_pointer_union("Pointer(Void)")
    union_type = converter.__test_type_ref_for_pointer_union("Nil | Pointer(Void)")
    descriptor = pointer_union_descriptor(converter, union_type, [
      {0, Adamas::HIR::TypeRef::NIL, "Nil"},
      {91, pointer_void, "Pointer(Void)"},
    ])
    converter.__test_replace_union_descriptor(union_type, descriptor)

    converter.__test_unwrap_pointer_union(union_type, nil).should be_nil
  end

  it "keeps custom ids stable when Nil is present and variants are reordered" do
    converter = pointer_union_converter
    pointer_u8 = converter.__test_type_ref_for_pointer_union("Pointer(UInt8)")
    pointer_void = converter.__test_type_ref_for_pointer_union("Pointer(Void)")
    union_type = converter.__test_type_ref_for_pointer_union("Nil | Pointer(Void) | Pointer(UInt8)")
    descriptor = pointer_union_descriptor(converter, union_type, [
      {0, Adamas::HIR::TypeRef::NIL, "Nil"},
      {19, pointer_void, "Pointer(Void)"},
      {73, pointer_u8, "Pointer(UInt8)"},
    ])
    converter.__test_replace_union_descriptor(union_type, descriptor)

    exact = converter.__test_unwrap_pointer_union(union_type, Adamas::HIR::TypeRef::UINT8)
    exact.should_not be_nil
    exact.not_nil!.variant_type_id.should eq(73)

    opaque = converter.__test_unwrap_pointer_union(union_type, Adamas::HIR::TypeRef::INT32, true)
    opaque.should_not be_nil
    opaque.not_nil!.type.should eq(pointer_void)
    opaque.not_nil!.variant_type_id.should eq(19)
  end

  it "reads the authoritative sidecar when the legacy descriptor hash is poisoned" do
    converter = pointer_union_converter
    pointer_u8 = converter.__test_type_ref_for_pointer_union("Pointer(UInt8)")
    pointer_void = converter.__test_type_ref_for_pointer_union("Pointer(Void)")
    union_type = converter.__test_type_ref_for_pointer_union("Pointer(UInt8) | Pointer(Void)")
    sidecar_descriptor = pointer_union_descriptor(converter, union_type, [
      {37, pointer_u8, "Pointer(UInt8)"},
      {91, pointer_void, "Pointer(Void)"},
    ])
    poison_descriptor = pointer_union_descriptor(converter, union_type, [
      {0, pointer_u8, "Pointer(UInt8)"},
      {1, pointer_void, "Pointer(Void)"},
    ])
    converter.__test_replace_union_descriptor(union_type, sidecar_descriptor)
    converter.__test_replace_union_descriptor_hash_only(union_type, poison_descriptor)

    unwrap = converter.__test_unwrap_pointer_union(union_type, Adamas::HIR::TypeRef::UINT8)
    unwrap.should_not be_nil
    unwrap.not_nil!.variant_type_id.should eq(37)
  end

  it "chooses the newest sidecar descriptor when refresh leaves duplicate entries" do
    converter = pointer_union_converter
    pointer_u8 = converter.__test_type_ref_for_pointer_union("Pointer(UInt8)")
    pointer_void = converter.__test_type_ref_for_pointer_union("Pointer(Void)")
    union_type = converter.__test_type_ref_for_pointer_union("Pointer(UInt8) | Pointer(Void)")
    stale_descriptor = pointer_union_descriptor(converter, union_type, [
      {0, pointer_u8, "Pointer(UInt8)"},
      {1, pointer_void, "Pointer(Void)"},
    ])
    latest_descriptor = pointer_union_descriptor(converter, union_type, [
      {37, pointer_u8, "Pointer(UInt8)"},
      {91, pointer_void, "Pointer(Void)"},
    ])
    converter.__test_replace_union_descriptor(union_type, stale_descriptor)
    converter.__test_append_union_descriptor_sidecar(union_type, latest_descriptor)
    converter.__test_replace_union_descriptor_hash_only(union_type, stale_descriptor)

    unwrap = converter.__test_unwrap_pointer_union(union_type, Adamas::HIR::TypeRef::UINT8)
    unwrap.should_not be_nil
    unwrap.not_nil!.variant_type_id.should eq(37)
  end

  it "does not unwrap a pointer arm from a mixed pointer-and-class union" do
    converter = pointer_union_converter
    pointer_u8 = converter.__test_type_ref_for_pointer_union("Pointer(UInt8)")
    widget = converter.__test_type_ref_for_pointer_union("Widget")
    union_type = converter.__test_type_ref_for_pointer_union("Pointer(UInt8) | Widget")
    descriptor = pointer_union_descriptor(converter, union_type, [
      {41, pointer_u8, "Pointer(UInt8)"},
      {97, widget, "Widget"},
    ])
    converter.__test_replace_union_descriptor(union_type, descriptor)

    converter.__test_unwrap_pointer_union(union_type, Adamas::HIR::TypeRef::UINT8).should be_nil
    converter.__test_unwrap_pointer_union(union_type, Adamas::HIR::TypeRef::INT32, true).should be_nil
    converter.__test_unwrap_pointer_union(union_type, Adamas::HIR::TypeRef::INT32).should be_nil
  end

  it "does not treat a PointerThing type name as a raw Pointer variant" do
    converter = pointer_union_converter
    pointer_u8 = converter.__test_type_ref_for_pointer_union("Pointer(UInt8)")
    pointer_thing = converter.__test_type_ref_for_pointer_union("PointerThing")
    union_type = converter.__test_type_ref_for_pointer_union("Pointer(UInt8) | PointerThing")
    descriptor = pointer_union_descriptor(converter, union_type, [
      {41, pointer_u8, "Pointer(UInt8)"},
      {97, pointer_thing, "PointerThing"},
    ])
    converter.__test_replace_union_descriptor(union_type, descriptor)

    converter.__test_unwrap_pointer_union(union_type, Adamas::HIR::TypeRef::UINT8).should be_nil
  end

  it "does not lower a mixed pointer-and-class value assignment as PointerStore" do
    function = lower_mixed_pointer_store_source
    instructions = function.blocks.flat_map(&.instructions)
    instructions.any? { |instruction| instruction.is_a?(Adamas::HIR::PointerStore) }.should be_false
    instructions.any? { |instruction| instruction.is_a?(Adamas::HIR::UnionUnwrap) }.should be_false
  end

  it "unwraps pointer unions before the inline set_crystal_type_id store" do
    function, converter = lower_pointer_union_set_type_id_source
    store = function.blocks.flat_map(&.instructions).find { |instruction| instruction.is_a?(Adamas::HIR::PointerStore) }
    store.should_not be_nil
    store = store.not_nil!.as(Adamas::HIR::PointerStore)

    unwrap = function.blocks.flat_map(&.instructions).find do |instruction|
      instruction.is_a?(Adamas::HIR::UnionUnwrap) && instruction.id == store.pointer
    end
    unwrap.should_not be_nil
    unwrap = unwrap.not_nil!.as(Adamas::HIR::UnionUnwrap)
    unwrap_desc = converter.module.get_type_descriptor(unwrap.type)
    unwrap_desc.should_not be_nil
    unwrap_desc.not_nil!.name.should eq("Pointer(Void)")
  end

  it "unwraps pointer unions before the qualified set_crystal_type_id store" do
    function, converter = lower_pointer_union_qualified_set_type_id_source
    store = function.blocks.flat_map(&.instructions).find { |instruction| instruction.is_a?(Adamas::HIR::PointerStore) }
    store.should_not be_nil
    store = store.not_nil!.as(Adamas::HIR::PointerStore)

    unwrap = function.blocks.flat_map(&.instructions).find do |instruction|
      instruction.is_a?(Adamas::HIR::UnionUnwrap) && instruction.id == store.pointer
    end
    unwrap.should_not be_nil
    unwrap_desc = converter.module.get_type_descriptor(unwrap.not_nil!.as(Adamas::HIR::UnionUnwrap).type)
    unwrap_desc.should_not be_nil
    unwrap_desc.not_nil!.name.should eq("Pointer(Void)")
  end

  it "covers the named-argument fallback set_crystal_type_id store path" do
    function, converter = lower_pointer_union_fallback_set_type_id_source
    store = function.blocks.flat_map(&.instructions).find { |instruction| instruction.is_a?(Adamas::HIR::PointerStore) }
    store.should_not be_nil
    store = store.not_nil!.as(Adamas::HIR::PointerStore)

    unwrap = function.blocks.flat_map(&.instructions).find do |instruction|
      instruction.is_a?(Adamas::HIR::UnionUnwrap) && instruction.id == store.pointer
    end
    unwrap.should_not be_nil
    unwrap_desc = converter.module.get_type_descriptor(unwrap.not_nil!.as(Adamas::HIR::UnionUnwrap).type)
    unwrap_desc.should_not be_nil
    unwrap_desc.not_nil!.name.should eq("Pointer(Void)")
  end

  it "normalizes the primitive pointer-set bypass for a pointer union" do
    converter = pointer_union_converter
    pointer_u8 = converter.__test_type_ref_for_pointer_union("Pointer(UInt8)")
    pointer_void = converter.__test_type_ref_for_pointer_union("Pointer(Void)")
    union_type = converter.__test_type_ref_for_pointer_union("Pointer(UInt8) | Pointer(Void)")

    function = converter.__test_lower_primitive_pointer_set(union_type, Adamas::HIR::TypeRef::INT32)
    store = function.blocks.flat_map(&.instructions).find { |instruction| instruction.is_a?(Adamas::HIR::PointerStore) }
    store.should_not be_nil
    store = store.not_nil!.as(Adamas::HIR::PointerStore)
    unwrap = function.blocks.flat_map(&.instructions).find do |instruction|
      instruction.is_a?(Adamas::HIR::UnionUnwrap) && instruction.id == store.pointer
    end
    unwrap.should_not be_nil
    converter.module.get_type_descriptor(pointer_u8).should_not be_nil
    converter.module.get_type_descriptor(pointer_void).should_not be_nil
  end

  it "does not emit a raw store or unwrap for a mixed pointer-and-class set-id union" do
    function = lower_mixed_pointer_union_set_type_id_source
    instructions = function.blocks.flat_map(&.instructions)
    instructions.any? { |instruction| instruction.is_a?(Adamas::HIR::PointerStore) }.should be_false
    instructions.any? { |instruction| instruction.is_a?(Adamas::HIR::UnionUnwrap) }.should be_false
  end

  it "keeps the named-argument fallback set-id path closed for a mixed union" do
    function = lower_mixed_pointer_union_fallback_set_type_id_source
    instructions = function.blocks.flat_map(&.instructions)
    instructions.any? { |instruction| instruction.is_a?(Adamas::HIR::PointerStore) }.should be_false
    instructions.any? { |instruction| instruction.is_a?(Adamas::HIR::UnionUnwrap) }.should be_false
  end

  it "does not guess the first typed pointer when no exact arm or Pointer(Void) exists" do
    converter = pointer_union_converter
    pointer_u8 = converter.__test_type_ref_for_pointer_union("Pointer(UInt8)")
    pointer_u16 = converter.__test_type_ref_for_pointer_union("Pointer(UInt16)")
    union_type = converter.__test_type_ref_for_pointer_union("Pointer(UInt8) | Pointer(UInt16)")
    descriptor = pointer_union_descriptor(converter, union_type, [
      {53, pointer_u8, "Pointer(UInt8)"},
      {89, pointer_u16, "Pointer(UInt16)"},
    ])
    converter.__test_replace_union_descriptor(union_type, descriptor)

    converter.__test_unwrap_pointer_union(union_type, Adamas::HIR::TypeRef::INT32).should be_nil
    converter.__test_unwrap_pointer_union(union_type, nil).should be_nil
    exact = converter.__test_unwrap_pointer_union(union_type, Adamas::HIR::TypeRef::UINT16)
    exact.should_not be_nil
    exact.not_nil!.variant_type_id.should eq(89)
  end

  it "lowers the Int32 pointer-union value assignment to an explicit raw-pointer store" do
    function, converter = lower_pointer_union_store_source
    store = function.blocks.flat_map(&.instructions).find { |instruction| instruction.is_a?(Adamas::HIR::PointerStore) }
    store.should_not be_nil
    store = store.not_nil!.as(Adamas::HIR::PointerStore)

    unwrap = function.blocks.flat_map(&.instructions).find do |instruction|
      instruction.is_a?(Adamas::HIR::UnionUnwrap) && instruction.id == store.pointer
    end
    unwrap.should_not be_nil
    unwrap = unwrap.not_nil!.as(Adamas::HIR::UnionUnwrap)
    unwrap_desc = converter.module.get_type_descriptor(unwrap.type)
    unwrap_desc.should_not be_nil
    unwrap_desc.not_nil!.name.should eq("Pointer(Void)")

    union_desc = converter.union_descriptors.values.find do |descriptor|
      descriptor.name == "Pointer(UInt8) | Pointer(Void)"
    end
    union_desc.should_not be_nil
    void_variant = union_desc.not_nil!.variants.find { |variant| variant.full_name == "Pointer(Void)" }
    void_variant.should_not be_nil
    unwrap.variant_type_id.should eq(void_variant.not_nil!.type_id)
  end

  it "lowers a pointer-union load through the sole concrete pointer arm" do
    function, converter = lower_pointer_union_load_source
    load = function.blocks.flat_map(&.instructions).find { |instruction| instruction.is_a?(Adamas::HIR::PointerLoad) }
    load.should_not be_nil
    load = load.not_nil!.as(Adamas::HIR::PointerLoad)
    load.type.should eq(Adamas::HIR::TypeRef::UINT8)

    unwrap = function.blocks.flat_map(&.instructions).find do |instruction|
      instruction.is_a?(Adamas::HIR::UnionUnwrap) && instruction.id == load.pointer
    end
    unwrap.should_not be_nil
    unwrap = unwrap.not_nil!.as(Adamas::HIR::UnionUnwrap)
    unwrap_desc = converter.module.get_type_descriptor(unwrap.type)
    unwrap_desc.should_not be_nil
    unwrap_desc.not_nil!.name.should eq("Pointer(UInt8)")
  end

  it "keeps the Int32 payload type on an indexed Pointer(Void) fallback store" do
    function, converter = lower_pointer_union_index_store_source
    store = function.blocks.flat_map(&.instructions).find { |instruction| instruction.is_a?(Adamas::HIR::PointerStore) }
    store.should_not be_nil
    store = store.not_nil!.as(Adamas::HIR::PointerStore)
    store.index.should_not be_nil
    stored_value = function.params.find { |param| param.id == store.value }
    unless stored_value
      stored_value = function.blocks.flat_map(&.instructions).find { |instruction| instruction.id == store.value }
    end
    stored_value.should_not be_nil
    stored_value.not_nil!.type.should eq(Adamas::HIR::TypeRef::INT32)

    unwrap = function.blocks.flat_map(&.instructions).find do |instruction|
      instruction.is_a?(Adamas::HIR::UnionUnwrap) && instruction.id == store.pointer
    end
    unwrap.should_not be_nil
    unwrap_desc = converter.module.get_type_descriptor(unwrap.not_nil!.as(Adamas::HIR::UnionUnwrap).type)
    unwrap_desc.should_not be_nil
    unwrap_desc.not_nil!.name.should eq("Pointer(Void)")
  end

  it "uses an explicit byte stride for Pointer(Void) fallback arithmetic" do
    function, converter = lower_pointer_union_add_source
    add = function.blocks.flat_map(&.instructions).find { |instruction| instruction.is_a?(Adamas::HIR::PointerAdd) }
    add.should_not be_nil
    add = add.not_nil!.as(Adamas::HIR::PointerAdd)
    add.element_type.should eq(Adamas::HIR::TypeRef::UINT8)
    add.element_byte_size.should eq(1_u64)

    unwrap = function.blocks.flat_map(&.instructions).find do |instruction|
      instruction.is_a?(Adamas::HIR::UnionUnwrap) && instruction.id == add.pointer
    end
    unwrap.should_not be_nil
    unwrap_desc = converter.module.get_type_descriptor(unwrap.not_nil!.as(Adamas::HIR::UnionUnwrap).type)
    unwrap_desc.should_not be_nil
    unwrap_desc.not_nil!.name.should eq("Pointer(Void)")
  end
end
