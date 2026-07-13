require "spec"
require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_function_body_type_literal(function : Function) : TypeRef?
    function_body_type_literal?(function)
  end

  def __test_receiver_value_type_literal(function : Function, receiver : ValueId) : TypeRef?
    receiver_value_type_literal?(function, receiver, {} of String => TypeRef?)
  end
end

describe "function body type-literal recovery" do
  it "fails closed on a non-Return terminator" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    function = Adamas::HIR::Function.new(0_u32, "non_return_type_literal_probe", Adamas::HIR::TypeRef::VOID)
    function.get_block(function.entry_block).terminator = Adamas::HIR::Unreachable.new

    converter.__test_function_body_type_literal(function).should be_nil
  end

  it "recovers a user type through a producer Call using a linear value scan" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    user_type = Adamas::HIR::TypeRef.new(Adamas::HIR::TypeRef::FIRST_USER_TYPE)
    target = converter.module.create_function("producer_target", user_type)
    literal = Adamas::HIR::Literal.new(target.next_value_id, user_type, 0_i64)
    target.get_block(target.entry_block).add(literal)
    target.get_block(target.entry_block).terminator = Adamas::HIR::Return.new(literal.id)

    producer = converter.module.create_function("producer", user_type)
    call = Adamas::HIR::Call.new(producer.next_value_id, user_type, "")
    call.configure_without_receiver("producer_target", [] of Adamas::HIR::ValueId)
    producer.get_block(producer.entry_block).add(call)

    converter.__test_receiver_value_type_literal(producer, call.id).should eq(user_type)
  end

  it "fails closed through a producer Call whose target returns a primitive literal" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    target = converter.module.create_function("primitive_target", Adamas::HIR::TypeRef::INT32)
    literal = Adamas::HIR::Literal.new(target.next_value_id, Adamas::HIR::TypeRef::INT32, 0_i64)
    target.get_block(target.entry_block).add(literal)
    target.get_block(target.entry_block).terminator = Adamas::HIR::Return.new(literal.id)

    producer = converter.module.create_function("primitive_producer", Adamas::HIR::TypeRef::INT32)
    call = Adamas::HIR::Call.new(producer.next_value_id, Adamas::HIR::TypeRef::INT32, "")
    call.configure_without_receiver("primitive_target", [] of Adamas::HIR::ValueId)
    producer.get_block(producer.entry_block).add(call)

    converter.__test_receiver_value_type_literal(producer, call.id).should be_nil
  end
end
