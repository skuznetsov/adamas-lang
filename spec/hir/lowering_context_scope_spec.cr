require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def parse_scope_probe(code : String) : {CrystalV2::Compiler::Frontend::ArenaLike, Array(CrystalV2::Compiler::Frontend::ExprId)}
  lexer = CrystalV2::Compiler::Frontend::Lexer.new(code)
  parser = CrystalV2::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  {result.arena, result.roots}
end

describe Crystal::HIR::LoweringContext do
  it "restores outer locals when a nested block scope exits" do
    arena, _exprs = parse_scope_probe("1")
    converter = Crystal::HIR::AstToHir.new(arena)
    func = converter.module.create_function("test_scope_restore", Crystal::HIR::TypeRef::VOID)
    ctx = Crystal::HIR::LoweringContext.new(func, converter.module, arena)

    outer = Crystal::HIR::Literal.new(ctx.next_id, Crystal::HIR::TypeRef::INT32, 1_i64)
    ctx.emit(outer)
    ctx.register_local("value", outer.id)

    ctx.push_scope(Crystal::HIR::ScopeKind::Block)
    shadow = Crystal::HIR::Literal.new(ctx.next_id, Crystal::HIR::TypeRef::INT32, 2_i64)
    ctx.emit(shadow)
    ctx.register_local("value", shadow.id)
    inner_only = Crystal::HIR::Literal.new(ctx.next_id, Crystal::HIR::TypeRef::INT32, 3_i64)
    ctx.emit(inner_only)
    ctx.register_local("inner_only", inner_only.id)

    ctx.lookup_local("value").should eq(shadow.id)
    ctx.lookup_local("inner_only").should eq(inner_only.id)

    ctx.pop_scope

    ctx.lookup_local("value").should eq(outer.id)
    ctx.lookup_local("inner_only").should be_nil
  end
end
