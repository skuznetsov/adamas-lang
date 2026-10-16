require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_union_receiver_char_ord_dispatch(char_first : Bool = true, with_argument : Bool = false) : Array(Adamas::HIR::Value)
    other_type = @module.intern_type(Adamas::HIR::TypeDescriptor.new(
      Adamas::HIR::TypeKind::Struct, "UnionOrdBox"))
    receiver_type = @module.intern_type(Adamas::HIR::TypeDescriptor.new(
      Adamas::HIR::TypeKind::Union,
      char_first ? "Char | UnionOrdBox" : "UnionOrdBox | Char",
      char_first ? [Adamas::HIR::TypeRef::CHAR, other_type] : [other_type, Adamas::HIR::TypeRef::CHAR]))

    @module.create_function("Char#ord", Adamas::HIR::TypeRef::INT32)
    @module.create_function("UnionOrdBox#ord", Adamas::HIR::TypeRef::INT32)

    function = @module.create_function("union_char_ord_caller", Adamas::HIR::TypeRef::INT32)
    receiver = function.add_param("receiver", receiver_type)
    ctx = Adamas::HIR::LoweringContext.new(function, @module, @arena)
    ctx.register_type(receiver.id, receiver.type)

    descriptor = @module.get_type_descriptor(receiver_type).not_nil!
    argument_ids = [] of Adamas::HIR::ValueId
    argument_types = [] of Adamas::HIR::TypeRef
    if with_argument
      argument = function.add_param("argument", Adamas::HIR::TypeRef::INT32)
      argument_ids << argument.id
      argument_types << argument.type
      ctx.register_type(argument.id, argument.type)
    end
    result = try_emit_union_receiver_dispatch(
      ctx, receiver.id, receiver_type, descriptor,
      "Char#ord", nil, argument_ids, argument_types,
      Adamas::HIR::TypeRef::INT32, false, nil,
    )
    result.should_not be_nil

    instructions = function.blocks.flat_map(&.instructions)
    instructions.select do |instruction|
      instruction.is_a?(Adamas::HIR::Cast) ||
        instruction.is_a?(Adamas::HIR::Call) ||
        instruction.is_a?(Adamas::HIR::UnionUnwrap)
    end
  end
end

describe "union receiver primitive dispatch" do
  {true, false}.each do |char_first|
    it "lowers Char#ord through the primitive Int32 cast with char_first=#{char_first}" do
      converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
      instructions = converter.__test_union_receiver_char_ord_dispatch(char_first)
      casts = instructions.select(Adamas::HIR::Cast)
      calls = instructions.select(Adamas::HIR::Call)
      char_unwraps = instructions.select(Adamas::HIR::UnionUnwrap).select do |unwrap|
        unwrap.type == Adamas::HIR::TypeRef::CHAR
      end
      casts.any? do |cast|
        cast.target_type == Adamas::HIR::TypeRef::INT32 &&
          char_unwraps.any? { |unwrap| unwrap.id == cast.value }
      end.should be_true
      calls.map(&.method_name).should_not contain("Char#ord")
      calls.map(&.method_name).should contain("UnionOrdBox#ord")
    end
  end

  it "does not replace an ordinary overload accepting an argument" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    instructions = converter.__test_union_receiver_char_ord_dispatch(with_argument: true)
    instructions.select(Adamas::HIR::Cast).should be_empty
    instructions.select(Adamas::HIR::Call).map(&.method_name).should contain("Char#ord$Int32")
  end
end
