require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_lower_aggregate_proc_value(ctx : LoweringContext, expression : ExprId) : ValueId
    lower_expr(ctx, expression)
  end
end

private def aggregate_proc_type_contract(source : String, class_result : Bool = false)
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(program.arena)
  callback_type = converter.module.intern_type(Adamas::HIR::TypeDescriptor.new(
    Adamas::HIR::TypeKind::Proc, "Proc",
    [Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::INT64],
    proc_type_literal_slots: [false, class_result],
  ))
  function = converter.module.create_function("aggregate_proc_type_probe", Adamas::HIR::TypeRef::VOID)
  ctx = Adamas::HIR::LoweringContext.new(function, converter.module, program.arena)
  callback = function.add_param("callback", callback_type)
  ctx.register_type(callback.id, callback_type)
  ctx.register_local("callback", callback.id)
  value = converter.__test_lower_aggregate_proc_value(ctx, program.roots.first)
  aggregate = converter.module.get_type_descriptor(ctx.type_of(value)).not_nil!
  {converter, callback_type, aggregate}
end

describe "aggregate callable source type contract" do
  it "retains a tuple element's complete callable type" do
    _, callback, tuple = aggregate_proc_type_contract("{callback}")
    tuple.type_params.should eq([callback])
  end

  it "retains a named tuple field's complete callable type" do
    _, callback, tuple = aggregate_proc_type_contract("{callback: callback}")
    tuple.type_params.should eq([callback])
  end

  it "retains callable value-kind slots through a nested tuple" do
    converter, callback, outer = aggregate_proc_type_contract("{ {callback} }", class_result: true)
    inner = converter.module.get_type_descriptor(outer.type_params.first).not_nil!
    inner.type_params.should eq([callback])
  end
end
