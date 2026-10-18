require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_proc_input_type_names(type_name : String) : Array(String)?
    proc_input_type_names(type_name)
  end

  def __test_proc_type_argument_names(type_name : String) : Array(String)?
    proc_type_argument_names(type_name)
  end
end

describe "grouped Proc type-name conversion" do
  it "splits a fully grouped two-input arrow signature" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)

    converter.__test_proc_input_type_names("(Void*, Void*) -> Int32").should eq(["Void*", "Void*"])
    converter.__test_proc_type_argument_names("(Void*, Void*) -> Int32").should eq(["Void*", "Void*", "Int32"])
  end

  it "preserves the exact zero-input arrow result contract" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)

    converter.__test_proc_input_type_names("() -> Nil").should eq([] of String)
    converter.__test_proc_type_argument_names("() -> Nil").should eq(["Nil"])
    converter.__test_proc_input_type_names("()").should be_nil
    converter.__test_proc_type_argument_names("()").should be_nil
  end

  it "keeps one nested Proc arrow as one outer input" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    nested = "((Int32) -> String) -> Bool"

    converter.__test_proc_input_type_names(nested).should eq(["((Int32) -> String)"])
    converter.__test_proc_type_argument_names(nested).should eq(["((Int32) -> String)", "Bool"])
  end

  it "removes grouping around one input without changing generic Proc arity" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)

    converter.__test_proc_input_type_names("(Int32) -> String").should eq(["Int32"])
    converter.__test_proc_type_argument_names("(Int32) -> String").should eq(["Int32", "String"])

    converter.__test_proc_input_type_names("Proc(Int32, String)").should eq(["Int32"])
    converter.__test_proc_type_argument_names("Proc(Int32, String)").should eq(["Int32", "String"])
  end

  it "keeps a union inside one grouped Proc input" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    grouped_union = "(String | Nil, Int32) -> Bool"

    converter.__test_proc_input_type_names(grouped_union).should eq(["String | Nil", "Int32"])
    converter.__test_proc_type_argument_names(grouped_union).should eq(["String | Nil", "Int32", "Bool"])
  end

  it "keeps a nested Proc and its sibling as separate inputs" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    nested_with_sibling = "((String, Int32 -> Int32), Bool) -> Bool"

    converter.__test_proc_input_type_names(nested_with_sibling).should eq(["(String, Int32 -> Int32)", "Bool"])
    converter.__test_proc_type_argument_names(nested_with_sibling).should eq(["(String, Int32 -> Int32)", "Bool", "Bool"])
  end
end
