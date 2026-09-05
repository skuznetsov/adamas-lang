require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

# Test-only access to the private detached-block return probe.  The production
# method remains private; this wrapper makes its CFG contract directly testable.
class Adamas::HIR::AstToHir
  def __test_block_return_type_name(
    ctx : Adamas::HIR::LoweringContext,
    block_id : Adamas::HIR::BlockId,
  ) : String?
    block_return_type_name(ctx, block_id)
  end
end

private record BlockReturnProbe,
  converter : Adamas::HIR::AstToHir,
  context : Adamas::HIR::LoweringContext,
  function : Adamas::HIR::Function

private def new_block_return_probe : BlockReturnProbe
  parsed = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new("")
  ).parse_program
  converter = Adamas::HIR::AstToHir.new(parsed.arena)
  function = converter.module.create_function("__block_return_probe", Adamas::HIR::TypeRef::VOID)
  context = Adamas::HIR::LoweringContext.new(function, converter.module, parsed.arena)
  BlockReturnProbe.new(converter, context, function)
end

private def add_int32_literal(
  context : Adamas::HIR::LoweringContext,
  block_id : Adamas::HIR::BlockId,
  value : Int64 = 1_i64,
) : Adamas::HIR::ValueId
  id = context.next_id
  context.emit_to_block(
    block_id,
    Adamas::HIR::Literal.new(id, Adamas::HIR::TypeRef::INT32, value),
  )
  id
end

private def add_string_literal(
  context : Adamas::HIR::LoweringContext,
  block_id : Adamas::HIR::BlockId,
) : Adamas::HIR::ValueId
  id = context.next_id
  context.emit_to_block(
    block_id,
    Adamas::HIR::Literal.new(id, Adamas::HIR::TypeRef::STRING, "unrelated"),
  )
  id
end

private def add_bool_literal(
  context : Adamas::HIR::LoweringContext,
  block_id : Adamas::HIR::BlockId,
) : Adamas::HIR::ValueId
  id = context.next_id
  context.emit_to_block(
    block_id,
    Adamas::HIR::Literal.new(id, Adamas::HIR::TypeRef::BOOL, true),
  )
  id
end

describe "AstToHir#block_return_type_name" do
  it "follows a jump from a detached entry to its return" do
    probe = new_block_return_probe
    entry = probe.function.entry_block
    target = probe.function.create_block(probe.function.scopes[0].id)
    value = add_int32_literal(probe.context, target)

    probe.function.get_block(entry).terminator = Adamas::HIR::Jump.new(target)
    probe.function.get_block(target).terminator = Adamas::HIR::Return.new(value)

    probe.converter.__test_block_return_type_name(probe.context, entry).should eq("Int32")
  end

  it "follows branches and ignores an unrelated return block" do
    probe = new_block_return_probe
    entry = probe.function.entry_block
    then_block = probe.function.create_block(probe.function.scopes[0].id)
    else_block = probe.function.create_block(probe.function.scopes[0].id)
    unrelated = probe.function.create_block(probe.function.scopes[0].id)
    condition = add_bool_literal(probe.context, entry)
    then_value = add_int32_literal(probe.context, then_block)
    else_value = add_int32_literal(probe.context, else_block, 2_i64)
    unrelated_value = add_string_literal(probe.context, unrelated)

    probe.function.get_block(entry).terminator = Adamas::HIR::Branch.new(condition, then_block, else_block)
    probe.function.get_block(then_block).terminator = Adamas::HIR::Return.new(then_value)
    probe.function.get_block(else_block).terminator = Adamas::HIR::Return.new(else_value)
    probe.function.get_block(unrelated).terminator = Adamas::HIR::Return.new(unrelated_value)

    probe.converter.__test_block_return_type_name(probe.context, entry).should eq("Int32")
  end

  it "rejects mixed reachable return types" do
    probe = new_block_return_probe
    entry = probe.function.entry_block
    then_block = probe.function.create_block(probe.function.scopes[0].id)
    else_block = probe.function.create_block(probe.function.scopes[0].id)
    condition = add_bool_literal(probe.context, entry)
    then_value = add_int32_literal(probe.context, then_block)
    else_value = add_string_literal(probe.context, else_block)

    probe.function.get_block(entry).terminator = Adamas::HIR::Branch.new(condition, then_block, else_block)
    probe.function.get_block(then_block).terminator = Adamas::HIR::Return.new(then_value)
    probe.function.get_block(else_block).terminator = Adamas::HIR::Return.new(else_value)

    probe.converter.__test_block_return_type_name(probe.context, entry).should be_nil
  end

  it "rejects a reachable valueless return" do
    probe = new_block_return_probe
    entry = probe.function.entry_block
    target = probe.function.create_block(probe.function.scopes[0].id)

    probe.function.get_block(entry).terminator = Adamas::HIR::Jump.new(target)
    probe.function.get_block(target).terminator = Adamas::HIR::Return.new

    probe.converter.__test_block_return_type_name(probe.context, entry).should be_nil
  end

  it "terminates on a reachable cycle while retaining a stable return" do
    probe = new_block_return_probe
    entry = probe.function.entry_block
    loop_block = probe.function.create_block(probe.function.scopes[0].id)
    return_block = probe.function.create_block(probe.function.scopes[0].id)
    condition = add_bool_literal(probe.context, loop_block)
    return_value = add_int32_literal(probe.context, return_block)

    probe.function.get_block(entry).terminator = Adamas::HIR::Jump.new(loop_block)
    probe.function.get_block(loop_block).terminator = Adamas::HIR::Branch.new(condition, loop_block, return_block)
    probe.function.get_block(return_block).terminator = Adamas::HIR::Return.new(return_value)

    probe.converter.__test_block_return_type_name(probe.context, entry).should eq("Int32")
  end
end
