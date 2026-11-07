require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_allocator_block_carrier(input_heap : Bool, output_heap : Bool, pointer_type : Bool = false, mismatched_type : Bool = false)
    callback_type = pointer_type ? TypeRef::POINTER : type_ref_for_name("Proc")
    caller = @module.create_function("carrier_caller", TypeRef::VOID)
    caller.heap_block_param = input_heap
    argument = caller.add_param("block", callback_type, is_block: true)
    ctx = LoweringContext.new(caller, @module, @arena)
    ctx.register_type(argument.id, argument.type)
    initializer = @module.create_function("Carrier#initialize", TypeRef::VOID)
    initializer.add_param("self", TypeRef::POINTER)
    initializer.add_param("block", mismatched_type ? TypeRef::POINTER : callback_type, is_block: true)
    initializer.heap_block_param = output_heap
    adapted = adapt_allocator_initializer_arguments(ctx, [argument.id], initializer)
    {original: argument.id, adapted: adapted.first, instructions: caller.blocks.flat_map(&.instructions)}
  end
  def __test_allocator_callback_signature(actual : String, expected : String)
    actual_type = type_ref_for_name(actual)
    expected_type = type_ref_for_name(expected)
    caller = @module.create_function("signature_caller", TypeRef::VOID)
    argument = caller.add_param("block", actual_type, is_block: true)
    ctx = LoweringContext.new(caller, @module, @arena)
    ctx.register_type(argument.id, argument.type)
    initializer = @module.create_function("Signature#initialize", TypeRef::VOID)
    initializer.add_param("self", TypeRef::POINTER)
    initializer.add_param("block", expected_type, is_block: true)
    initializer.heap_block_param = true
    adapted = adapt_allocator_initializer_arguments(ctx, [argument.id], initializer)
    {adapted: adapted.first, instructions: caller.blocks.flat_map(&.instructions)}
  end
end

private def allocator_block_carrier_converter
  parsed = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new("1")
  ).parse_program
  Adamas::HIR::AstToHir.new(parsed.arena)
end

describe "completed initializer block carrier" do
  it "forwards a nominal Proc that the completed callee consumes as a raw callback" do
    result = allocator_block_carrier_converter.__test_allocator_block_carrier(false, false)
    result[:adapted].should eq(result[:original])
    result[:instructions].any?(&.is_a?(Adamas::HIR::MakeProc)).should be_false
  end

  it "forwards an untyped raw pointer without inventing a heap carrier" do
    result = allocator_block_carrier_converter.__test_allocator_block_carrier(false, false, pointer_type: true)
    result[:adapted].should eq(result[:original])
    result[:instructions].any?(&.is_a?(Adamas::HIR::MakeProc)).should be_false
  end

  it "materializes the same raw nominal Proc when the completed callee consumes a heap Proc" do
    result = allocator_block_carrier_converter.__test_allocator_block_carrier(false, true)
    result[:adapted].should_not eq(result[:original])
    result[:instructions].any?(&.is_a?(Adamas::HIR::MakeProc)).should be_true
  end

  it "preserves an existing heap Proc when both sides consume a heap carrier" do
    result = allocator_block_carrier_converter.__test_allocator_block_carrier(true, true)
    result[:adapted].should eq(result[:original])
    result[:instructions].any?(&.is_a?(Adamas::HIR::MakeProc)).should be_false
  end

  it "rejects a heap Proc passed to a raw formal despite an equal nominal type" do
    expect_raises(Adamas::HIR::LoweringError, /completed initializer raw block ABI disagrees/) do
      allocator_block_carrier_converter.__test_allocator_block_carrier(true, false)
    end
  end

  it "rejects a raw callback with a different completed nominal ABI" do
    expect_raises(Adamas::HIR::LoweringError, /completed initializer raw block ABI disagrees/) do
      allocator_block_carrier_converter.__test_allocator_block_carrier(false, false, mismatched_type: true)
    end
  end
end


describe "allocator raw-to-heap callback signature" do
  it "rejects changing the raw callback input ABI while boxing it" do
    expect_raises(Adamas::HIR::LoweringError, /completed initializer block ABI disagrees/) do
      allocator_block_carrier_converter.__test_allocator_callback_signature("Proc(Int32, Int32)", "Proc(String, Int32)")
    end
  end

  it "rejects changing the raw callback result ABI while boxing it" do
    expect_raises(Adamas::HIR::LoweringError, /completed initializer block ABI disagrees/) do
      allocator_block_carrier_converter.__test_allocator_callback_signature("Proc(Int32, Int32)", "Proc(Int32, Int64)")
    end
  end

  it "does not implement a Void output adapter by changing only the boxed pointer type" do
    expect_raises(Adamas::HIR::LoweringError, /completed initializer block ABI disagrees/) do
      allocator_block_carrier_converter.__test_allocator_callback_signature("Proc(Int32, Int32)", "Proc(Int32, Void)")
    end
  end
end
