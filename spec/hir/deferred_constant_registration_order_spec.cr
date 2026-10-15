require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_constant_registration_order
    sort_deferred_constant_inits!
    @deferred_constant_inits.map { |entry| deferred_constant_full_name(entry.owner, entry.name) }
  end
end

private def register_constant_source(converter, source)
  parsed = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source)).parse_program
  converter.arena = parsed.arena
  parsed.roots.each do |root|
    node = parsed.arena[root].as(Adamas::Compiler::Frontend::ConstantNode)
    converter.register_constant(node)
  end
end

describe "deferred constant source registration order" do
  it "does not compare line numbers from separate source arenas" do
    parsed = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new("")).parse_program
    converter = Adamas::HIR::AstToHir.new(parsed.arena)
    register_constant_source(converter, "\n" * 30 + "PROVIDER = {42}\n")
    register_constant_source(converter, "CONSUMER = {7}\n")
    converter.__test_constant_registration_order.should eq(["PROVIDER", "CONSUMER"])
  end

  it "keeps bare runtime constant aliases in dependency order" do
    parsed = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new("")).parse_program
    converter = Adamas::HIR::AstToHir.new(parsed.arena)
    register_constant_source(converter, "ALIAS = SOURCE\nSOURCE = {42}\n")
    converter.__test_constant_registration_order.should eq(["SOURCE", "ALIAS"])
  end

  it "retains direct dependency ordering for a forward reference" do
    parsed = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new("")).parse_program
    converter = Adamas::HIR::AstToHir.new(parsed.arena)
    register_constant_source(converter, "FIRST = SECOND[0]\nSECOND = {42}\n")
    converter.__test_constant_registration_order.should eq(["SECOND", "FIRST"])
  end
end
