require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_nullable_branch_type(expr_id : Adamas::Compiler::Frontend::ExprId) : String?
    infer_type_from_expr(expr_id, nil).try { |type| generic_param_type_name_from_ref(type) }
  end
end

private def nullable_branch_type(source : String) : String?
  parsed = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source)).parse_program
  converter = Adamas::HIR::AstToHir.new(
    parsed.arena,
    sources_by_arena: {parsed.arena.object_id.to_u64 => source},
  )
  converter.__test_nullable_branch_type(parsed.roots.first)
end

describe "nullable Proc branch inference" do
  it "infers an explicitly typed Proc literal" do
    nullable_branch_type("->(value : Int32) { 42 }").should eq("Proc(Int32, Int32)")
  end

  it "retains a Proc alongside Nil" do
    nullable_branch_type("if true\n->(value : Int32) { 42 }\nelse\nnil\nend")
      .not_nil!.split(" | ").sort.should eq(["Nil", "Proc(Int32, Int32)"])
  end

  it "does not guess an untyped Proc signature" do
    nullable_branch_type("->(value) { 42 }").should be_nil
  end

  [
    {"if", "if true\nunknown_source\nelse\n42\nend"},
    {"case", "case true\nwhen true\nunknown_source\nelse\n42\nend"},
    {"ternary", "true ? unknown_source : 42"},
    {"rescue", "begin\nunknown_source\nrescue\n42\nend"},
  ].each do |label, source|
    it "keeps an unknown #{label} arm unknown instead of dropping it" do
      nullable_branch_type(source).should be_nil
    end
  end

  it "includes Nil for an empty then branch" do
    nullable_branch_type("if true\nelse\n42\nend")
      .not_nil!.split(" | ").sort.should eq(["Int32", "Nil"])
  end

  it "includes Nil for an empty elsif branch" do
    nullable_branch_type("if true\n42\nelsif false\nelse\n43\nend")
      .not_nil!.split(" | ").sort.should eq(["Int32", "Nil"])
  end

  it "preserves the type of known branches" do
    nullable_branch_type("true ? 42 : 43").should eq("Int32")
  end
end
