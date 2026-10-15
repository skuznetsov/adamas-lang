require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_tuple_literal_range(node : Adamas::Compiler::Frontend::IndexNode, shape : String, range_type : String?)
    function = @module.create_function("tuple_range_probe", TypeRef::NIL)
    receiver = function.add_param("values", type_ref_for_name(shape))
    ctx = LoweringContext.new(function, @module, @arena)
    ctx.register_type(receiver.id, receiver.type)
    ctx.register_local("values", receiver.id)
    if range_type
      range = function.add_param("range", type_ref_for_name(range_type))
      ctx.register_type(range.id, range.type)
      ctx.register_local("range", range.id)
    end
    result = lower_index(ctx, node)
    {get_type_name_from_ref(ctx.type_of(result)), function, result, receiver.id}
  end
end

private def tuple_literal_range_probe(index : String, shape : String = "Tuple(Int32, Int64, Bool)", range_type : String? = nil)
  source = "values[#{index}]"
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  parsed = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(parsed.arena)
  node = parsed.arena[parsed.roots.first].as(Adamas::Compiler::Frontend::IndexNode)
  converter.__test_tuple_literal_range(node, shape, range_type)
end

describe "literal Tuple range indexing" do
  it "dispatches a runtime Range through the source method instead of scalar IndexGet" do
    _, function, _, _ = tuple_literal_range_probe("range", range_type: "Range(Int32, Int32)")
    instructions = function.blocks.flat_map(&.instructions)
    instructions.select(Adamas::HIR::IndexGet).should be_empty
    instructions.select(Adamas::HIR::Call).size.should eq(1)
    instructions.select(Adamas::HIR::Call).first.method_name.should contain("Range")
  end

  {
    "0..1"    => {"Tuple(Int32, Int64)", [0_i64, 1_i64]},
    "0...2"   => {"Tuple(Int32, Int64)", [0_i64, 1_i64]},
    "-2..-1"  => {"Tuple(Int64, Bool)", [1_i64, 2_i64]},
    "-3...-1" => {"Tuple(Int32, Int64)", [0_i64, 1_i64]},
    "1..99"   => {"Tuple(Int64, Bool)", [1_i64, 2_i64]},
    "..1"     => {"Tuple(Int32, Int64)", [0_i64, 1_i64]},
    "2.."     => {"Tuple(Bool)", [2_i64]},
    "0...0"   => {"Tuple()", [] of Int64},
    "1..-99"  => {"Tuple()", [] of Int64},
    "3..3"    => {"Tuple()", [] of Int64},
  }.each do |range, expected|
    it "preserves element order and shape for #{range}" do
      shape, function, result, receiver = tuple_literal_range_probe(range)
      shape.should eq(expected[0])
      instructions = function.blocks.flat_map(&.instructions)
      allocation = instructions.find { |inst| inst.id == result }.as(Adamas::HIR::Allocate)
      indexes = instructions.select(Adamas::HIR::IndexGet)
      allocation.constructor_args.should eq(indexes.map(&.id))
      copies = instructions.select(Adamas::HIR::Copy).select { |copy| copy.source == receiver }
      copies.size.should eq(1)
      indexes.map(&.object).should eq(Array.new(expected[1].size, copies.first.id))
      literal_indexes = indexes.map do |index|
        instructions.find { |inst| inst.id == index.index }.as(Adamas::HIR::Literal).value
      end
      literal_indexes.should eq(expected[1])
      instructions.select(Adamas::HIR::Call).should be_empty
    end
  end

  it "admits an empty tuple slice" do
    shape, _, _, _ = tuple_literal_range_probe("0..1", "Tuple()")
    shape.should eq("Tuple()")
  end

  ["4..5", "-4..1"].each do |range|
    it "rejects an out-of-bounds start #{range}" do
      expect_raises(Adamas::HIR::LoweringError, /begin index out of bounds/) do
        tuple_literal_range_probe(range)
      end
    end
  end

  ["0_i64..1", "0..1_i64"].each do |range|
    it "retains source dispatch for non-Int32 endpoints #{range}" do
      _, function, _, _ = tuple_literal_range_probe(range)
      function.blocks.flat_map(&.instructions).select(Adamas::HIR::IndexGet).should be_empty
    end
  end
end
