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

  it "does not add Nil to explicit returns inside non-exiting conditional loops" do
    converter = lower_reachable_method_tail_probe
    ["ReachableTailModule.", "ReachableTailClass#"].each do |owner|
      reachable_tail_type_parts(converter, owner + "return_only_while").should eq(["UInt32"])
      reachable_tail_type_parts(converter, owner + "return_only_until").should eq(["Nil", "UInt32"])
    end
  end

  it "uses only reachable break values when the condition cannot exit" do
    converter = lower_reachable_method_tail_probe
    ["ReachableTailModule.", "ReachableTailClass#"].each do |owner|
      reachable_tail_type_parts(converter, owner + "while_break_value").should eq(["Int32"])
      reachable_tail_type_parts(converter, owner + "until_break_value").should eq(["Int32", "Nil"])
      reachable_tail_type_parts(converter, owner + "while_mixed_break")
        .should eq(["Int32", "String"])
    end
  end

  it "retains Nil from reachable condition exits and valueless breaks" do
    converter = lower_reachable_method_tail_probe
    ["ReachableTailModule.", "ReachableTailClass#"].each do |owner|
      ["while_normal_exit", "until_normal_exit", "until_bare_break"].each do |method|
        reachable_tail_type_parts(converter, owner + method).should eq(["Int32", "Nil"])
      end
    end
  end

  it "gives a conditional loop with no returning exit a NoReturn result" do
    converter = lower_reachable_method_tail_probe
    ["ReachableTailModule.", "ReachableTailClass#"].each do |owner|
      reachable_tail_type_parts(converter, owner + "endless_while").should eq(["NoReturn"])
      function = reachable_tail_function(converter, owner + "endless_while")
      function.blocks.none? { |block| block.terminator.is_a?(Adamas::HIR::Return) }.should be_true
      reachable_tail_type_parts(converter, owner + "endless_until").should eq(["Nil"])
    end
  end
end
