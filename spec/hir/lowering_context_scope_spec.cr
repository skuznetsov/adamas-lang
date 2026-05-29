require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def parse_scope_probe(code : String) : {Adamas::Compiler::Frontend::ArenaLike, Array(Adamas::Compiler::Frontend::ExprId)}
  lexer = Adamas::Compiler::Frontend::Lexer.new(code)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  {result.arena, result.roots}
end

describe Adamas::HIR::LoweringContext do
  it "restores outer locals when a nested block scope exits" do
    arena, _exprs = parse_scope_probe("1")
    converter = Adamas::HIR::AstToHir.new(arena)
    func = converter.module.create_function("test_scope_restore", Adamas::HIR::TypeRef::VOID)
    ctx = Adamas::HIR::LoweringContext.new(func, converter.module, arena)

    outer = Adamas::HIR::Literal.new(ctx.next_id, Adamas::HIR::TypeRef::INT32, 1_i64)
    ctx.emit(outer)
    ctx.register_local("value", outer.id)

    ctx.push_scope(Adamas::HIR::ScopeKind::Block)
    shadow = Adamas::HIR::Literal.new(ctx.next_id, Adamas::HIR::TypeRef::INT32, 2_i64)
    ctx.emit(shadow)
    ctx.register_local("value", shadow.id)
    inner_only = Adamas::HIR::Literal.new(ctx.next_id, Adamas::HIR::TypeRef::INT32, 3_i64)
    ctx.emit(inner_only)
    ctx.register_local("inner_only", inner_only.id)

    ctx.lookup_local("value").should eq(shadow.id)
    ctx.lookup_local("inner_only").should eq(inner_only.id)

    ctx.pop_scope

    ctx.lookup_local("value").should eq(outer.id)
    ctx.lookup_local("inner_only").should be_nil
  end
end
