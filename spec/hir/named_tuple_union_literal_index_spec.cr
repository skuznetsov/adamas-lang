require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_named_tuple_literal_index(owner : String, key : String, nilable : Bool)
    receiver_type = type_ref_for_name(owner)
    function = @module.create_function("named_tuple_index_guard", TypeRef::NIL)
    receiver = function.add_param("receiver", receiver_type)
    ctx = LoweringContext.new(function, @module, @arena)
    ctx.register_type(receiver.id, receiver_type)
    result = lower_named_tuple_literal_index(ctx, receiver.id, key, nilable)
    result_name = result ? get_type_name_from_ref(ctx.type_of(result)) : nil
    {function, result_name}
  end
end

private def named_tuple_literal_index_converter
  Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
end

describe "literal key indexing on NamedTuple values" do
  it "preserves the exact field type for optional access to an existing key" do
    function, result = named_tuple_literal_index_converter.__test_named_tuple_literal_index(
      "NamedTuple(name: String, value: Int64)", "value", true)
    result.should eq("Int64")
    function.blocks.flat_map(&.instructions).select(Adamas::HIR::IndexGet).size.should eq(1)
  end

  it "returns Nil for an absent optional key on a concrete named tuple" do
    function, result = named_tuple_literal_index_converter.__test_named_tuple_literal_index(
      "NamedTuple(value: Int32)", "labels", true)
    result.should eq("Nil")
    function.blocks.flat_map(&.instructions).select(Adamas::HIR::IndexGet).should be_empty
  end

  it "selects each union arm's own field offset and merges distinct field types" do
    function, result = named_tuple_literal_index_converter.__test_named_tuple_literal_index(
      "NamedTuple(other: UInt8, value: Int32) | NamedTuple(value: Int64, other: UInt16)", "value", false)
    result.should eq("Int32 | Int64")
    instructions = function.blocks.flat_map(&.instructions)
    instructions.select(Adamas::HIR::UnionIs).size.should eq(1)
    instructions.select(Adamas::HIR::UnionUnwrap).size.should eq(2)
    gets = instructions.select(Adamas::HIR::IndexGet)
    gets.size.should eq(2)
    indices = gets.map { |get| instructions.find { |value| value.id == get.index }.as(Adamas::HIR::Literal).value }
    indices.sort_by(&.to_s).should eq([0_i64, 1_i64])
  end

  it "adds Nil only for union arms missing an optional key" do
    function, result = named_tuple_literal_index_converter.__test_named_tuple_literal_index(
      "NamedTuple(value: Int32) | NamedTuple(value: Int64, label: String)", "label", true)
    result.should eq("Nil | String")
    function.blocks.flat_map(&.instructions).select(Adamas::HIR::IndexGet).size.should eq(1)
  end

  it "keeps a union-valued field and adds the missing-arm Nil" do
    _, result = named_tuple_literal_index_converter.__test_named_tuple_literal_index(
      "NamedTuple(value: Int32) | NamedTuple(value: UInt16, label: Int32 | Int64)", "label", true)
    result.should eq("Nil | Int32 | Int64")
  end

  it "rejects a required key missing from any named tuple union arm" do
    expect_raises(Adamas::HIR::LoweringError, "missing key 'label'") do
      named_tuple_literal_index_converter.__test_named_tuple_literal_index(
        "NamedTuple(value: Int32) | NamedTuple(value: Int64, label: String)", "label", false)
    end
  end

  it "declines mixed receiver unions without emitting a partial dispatch" do
    function, result = named_tuple_literal_index_converter.__test_named_tuple_literal_index(
      "NamedTuple(value: Int32) | String", "value", true)
    result.should be_nil
    function.blocks.all?(&.instructions.empty?).should be_true
  end
end
