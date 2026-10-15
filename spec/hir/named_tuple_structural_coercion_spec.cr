require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_named_tuple_coercion(source : String, target : String)
    source_type = type_ref_for_name(source)
    target_type = type_ref_for_name(target)
    function = @module.create_function("named_tuple_coercion_guard", TypeRef::NIL)
    argument = function.add_param("value", source_type)
    ctx = LoweringContext.new(function, @module, @arena)
    ctx.register_type(argument.id, source_type)
    result = coerce_value_to_type(ctx, argument.id, target_type)
    {function, get_type_name_from_ref(ctx.type_of(result))}
  end

  def __test_named_tuple_first_union_variant(type : Adamas::HIR::TypeRef) : Int32
    ensure_union_descriptor_for_type_ref(type)
    union_descriptor_from_sidecar(type).not_nil!.variants.first.type_id
  end

  def __test_deferred_named_tuple_coercion
    source_type = type_ref_for_name("NamedTuple(value: Int32)")
    target_type = type_ref_for_name("NamedTuple(value: Int32 | Int64)")
    caller = @module.create_function("deferred_named_tuple_caller", TypeRef::NIL)
    argument = caller.add_param("value", source_type)
    call = Call.without_receiver(caller.next_value_id, TypeRef::NIL, "deferred_named_tuple_target", [argument.id])
    caller.get_block(caller.entry_block).add(call)
    # Publish the callee only after the caller has already been emitted.
    target = @module.create_function("deferred_named_tuple_target", TypeRef::NIL)
    target.add_param("value", target_type)
    repair_named_tuple_call_arguments
    first_size = caller.blocks.sum(&.instructions.size)
    repair_named_tuple_call_arguments
    {caller, call, first_size, target_type}
  end
end

private def named_tuple_structural_coercion_converter
  Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
end

describe "structural NamedTuple argument coercion" do
  it "reorders keys and wraps a widened field in the target layout" do
    function, result = named_tuple_structural_coercion_converter.__test_named_tuple_coercion(
      "NamedTuple(value: UInt16, label: Int32)", "NamedTuple(label: Int32 | Int64, value: UInt16)")
    result.should eq("NamedTuple(label: Int32 | Int64, value: UInt16)")
    instructions = function.blocks.flat_map(&.instructions)
    indices = instructions.select(Adamas::HIR::IndexGet).map do |get|
      instructions.find { |value| value.id == get.index }.as(Adamas::HIR::Literal).value
    end
    indices.should eq([1_i64, 0_i64])
    instructions.select(Adamas::HIR::UnionWrap).size.should eq(1)
    instructions.select(Adamas::HIR::Allocate).size.should eq(1)
  end

  it "rebuilds a compatible named tuple before embedding it in a union" do
    function, _ = named_tuple_structural_coercion_converter.__test_named_tuple_coercion(
      "NamedTuple(value: UInt16, label: Int32)",
      "NamedTuple(value: Int32) | NamedTuple(value: UInt16, label: Int32 | Int64)")
    instructions = function.blocks.flat_map(&.instructions)
    instructions.select(Adamas::HIR::Allocate).size.should eq(1)
    instructions.select(Adamas::HIR::UnionWrap).size.should eq(2)
  end

  it "accepts the first compatible member when more than one member is assignable" do
    converter = named_tuple_structural_coercion_converter
    function, _ = converter.__test_named_tuple_coercion(
      "NamedTuple(a: Int32, b: Int32)",
      "NamedTuple(a: Int32 | Int64, b: Int32) | NamedTuple(a: Int32, b: Int32 | Int64)")
    instructions = function.blocks.flat_map(&.instructions)
    instructions.select(Adamas::HIR::Allocate).size.should eq(1)
    outer = instructions.select(Adamas::HIR::UnionWrap).last
    outer.variant_type_id.should eq(converter.__test_named_tuple_first_union_variant(outer.type))
  end

  it "prefers an exact member without allocating a converted named tuple" do
    function, _ = named_tuple_structural_coercion_converter.__test_named_tuple_coercion(
      "NamedTuple(value: Int32)", "NamedTuple(value: Int32) | NamedTuple(value: Int32 | Int64)")
    instructions = function.blocks.flat_map(&.instructions)
    instructions.select(Adamas::HIR::Allocate).should be_empty
    instructions.select(Adamas::HIR::UnionWrap).size.should eq(1)
  end

  it "repairs a deferred call once after the exact callee publishes its layout" do
    function, call, first_size, target_type = named_tuple_structural_coercion_converter.__test_deferred_named_tuple_coercion
    instructions = function.blocks.flat_map(&.instructions)
    instructions.size.should eq(first_size)
    instructions.select(Adamas::HIR::Allocate).size.should eq(1)
    converted = instructions.find { |value| value.id == call.args.first }.not_nil!
    converted.type.should eq(target_type)
    instructions.index(converted).not_nil!.should be < instructions.index(call).not_nil!
  end
end
