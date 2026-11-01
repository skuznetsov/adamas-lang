require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def generic_readiness_converter(source : String = "") : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(program.arena,
    sources_by_arena: {program.arena.object_id.to_u64 => source})
  converter.no_prelude = true
  program.roots.each do |root|
    node = program.arena[root]
    converter.register_class(node) if node.is_a?(Adamas::Compiler::Frontend::ClassNode)
  end
  converter
end

class Adamas::HIR::AstToHir
  def __test_generic_readiness(name : String) : Bool
    !unresolved_generic_type_arg?(name)
  end

  def __test_rooted_union_cache_unchanged : {Bool, Array(String), Array(String)}
    name = "Int32 | ::Int64"
    before = split_union_type_name(name).dup
    ready = !unresolved_generic_type_arg?("::#{name}")
    {ready, before, split_union_type_name(name)}
  end
end

describe "generic union readiness" do
  it "keeps the shared union split cache immutable while checking a root-qualified first arm" do
    result = generic_readiness_converter.__test_rooted_union_cache_unchanged
    result[0].should be_true
    result[2].should eq(result[1])
  end

  it "recognizes Nil as a compiler-defined type before prelude registration" do
    generic_readiness_converter.__test_generic_readiness("Nil").should be_true
    generic_readiness_converter.__test_generic_readiness("Int64?").should be_true
    generic_readiness_converter.__test_generic_readiness("Int32 | Nil").should be_true
  end

  it "rejects unknown union arms and unresolved generic parameters" do
    converter = generic_readiness_converter
    converter.__test_generic_readiness("Int32 | MissingUnionArm").should be_false
    converter.__test_generic_readiness("Int32 | T").should be_false
    converter.__test_generic_readiness("Tuple(Int32, T)").should be_false
  end
end
