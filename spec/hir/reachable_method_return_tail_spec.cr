require "spec"
require "compiler/hir/hir"
require "compiler/hir/ast_to_hir"
require "compiler/frontend/parser"
require "compiler/frontend/lexer"

private def lower_reachable_method_tail_probe : Adamas::HIR::AstToHir
  source = File.read(File.join(__DIR__, "../fixtures/reachable_method_tail/reachable_method_tail.cr"))
  parsed = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  ).parse_program
  arena = parsed.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
  )
  converter.arena = arena

  modules = parsed.roots.compact_map do |expr_id|
    arena[expr_id].as?(Adamas::Compiler::Frontend::ModuleNode)
  end
  classes = parsed.roots.compact_map do |expr_id|
    arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
  end

  modules.each { |node| converter.register_module(node) }
  classes.each { |node| converter.register_class(node) }
  modules.each { |node| converter.lower_module(node) }
  classes.each { |node| converter.lower_class(node) }
  converter
end

class Adamas::HIR::AstToHir
  def __test_reachable_tail_type_name(type_ref : Adamas::HIR::TypeRef) : String
    get_type_name_from_ref(type_ref)
  end
end

private def reachable_tail_function(
  converter : Adamas::HIR::AstToHir,
  base_name : String,
) : Adamas::HIR::Function
  matches = converter.module.functions.select do |function|
    function.name == base_name || function.name.starts_with?(base_name + "$")
  end
  matches.size.should eq(1)
  matches.first
end

private def reachable_tail_type_parts(
  converter : Adamas::HIR::AstToHir,
  base_name : String,
) : Array(String)
  type_name = converter.__test_reachable_tail_type_name(
    reachable_tail_function(converter, base_name).return_type,
  )
  type_name.split(" | ").sort
end

describe "reachable method return tails" do
  it "infers Int32 after an explicit terminal return in module and class methods" do
    converter = lower_reachable_method_tail_probe

    reachable_tail_function(converter, "ReachableTailModule.explicit_terminal").return_type
      .should eq(Adamas::HIR::TypeRef::INT32)
    reachable_tail_function(converter, "ReachableTailClass#explicit_terminal").return_type
      .should eq(Adamas::HIR::TypeRef::INT32)
  end

  it "infers Int32 when every conditional branch returns" do
    converter = lower_reachable_method_tail_probe

    reachable_tail_function(converter, "ReachableTailModule.all_branches_terminal").return_type
      .should eq(Adamas::HIR::TypeRef::INT32)
    reachable_tail_function(converter, "ReachableTailClass#all_branches_terminal").return_type
      .should eq(Adamas::HIR::TypeRef::INT32)
  end

  it "keeps a reachable Nil tail in the return union" do
    converter = lower_reachable_method_tail_probe

    reachable_tail_type_parts(converter, "ReachableTailModule.nil_tail_after_return")
      .should eq(["Int32", "Nil"])
    reachable_tail_type_parts(converter, "ReachableTailClass#nil_tail_after_return")
      .should eq(["Int32", "Nil"])
  end

  it "keeps a reachable String tail in the return union" do
    converter = lower_reachable_method_tail_probe

    reachable_tail_type_parts(converter, "ReachableTailModule.string_tail_after_return")
      .should eq(["Int32", "String"])
    reachable_tail_type_parts(converter, "ReachableTailClass#string_tail_after_return")
      .should eq(["Int32", "String"])
  end
end
