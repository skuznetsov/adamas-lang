require "spec"
require "../../src/compiler/frontend/parser"

module ParserNamespaceWrapperSpec
  def self.parse(source : String)
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.should be_empty
    program
  end
end

describe "ModuleNode namespace wrapper provenance" do
  it "keeps explicit modules real even when each has a single nested declaration" do
    program = ParserNamespaceWrapperSpec.parse("module Outer\nmodule Inner\nclass Leaf\nend\nend\nend")
    arena = program.arena
    outer = arena[program.roots.first].as(Adamas::Compiler::Frontend::ModuleNode)
    inner = arena[outer.body.not_nil!.first].as(Adamas::Compiler::Frontend::ModuleNode)

    String.new(outer.name).should eq("Outer")
    String.new(inner.name).should eq("Inner")
    outer.namespace_wrapper.should be_false
    inner.namespace_wrapper.should be_false
    outer.absolute.should be_false
    inner.absolute.should be_false
  end

  it "marks every outer path segment of a qualified class" do
    program = ParserNamespaceWrapperSpec.parse("class Outer::Middle::Leaf\nend")
    arena = program.arena
    outer = arena[program.roots.first].as(Adamas::Compiler::Frontend::ModuleNode)
    middle = arena[outer.body.not_nil!.first].as(Adamas::Compiler::Frontend::ModuleNode)
    leaf = arena[middle.body.not_nil!.first].as(Adamas::Compiler::Frontend::ClassNode)

    String.new(outer.name).should eq("Outer")
    String.new(middle.name).should eq("Middle")
    String.new(leaf.name).should eq("Leaf")
    outer.namespace_wrapper.should be_true
    middle.namespace_wrapper.should be_true
    outer.absolute.should be_false
    middle.absolute.should be_false
    leaf.absolute.should be_false
  end

  it "keeps the innermost qualified generic module real" do
    program = ParserNamespaceWrapperSpec.parse("module Outer::Middle::Leaf(T)\nend")
    arena = program.arena
    outer = arena[program.roots.first].as(Adamas::Compiler::Frontend::ModuleNode)
    middle = arena[outer.body.not_nil!.first].as(Adamas::Compiler::Frontend::ModuleNode)
    leaf = arena[middle.body.not_nil!.first].as(Adamas::Compiler::Frontend::ModuleNode)

    outer.namespace_wrapper.should be_true
    middle.namespace_wrapper.should be_true
    leaf.namespace_wrapper.should be_false
    outer.type_params.should be_nil
    middle.type_params.should be_nil
    leaf.type_params.not_nil!.map { |name| String.new(name) }.should eq(["T"])
  end

  it "keeps an enclosing real module distinct from an absolute class path" do
    program = ParserNamespaceWrapperSpec.parse("module Enclosing\nclass ::Outer::Middle::Leaf\nend\nend")
    arena = program.arena
    enclosing = arena[program.roots.first].as(Adamas::Compiler::Frontend::ModuleNode)
    outer = arena[enclosing.body.not_nil!.first].as(Adamas::Compiler::Frontend::ModuleNode)
    middle = arena[outer.body.not_nil!.first].as(Adamas::Compiler::Frontend::ModuleNode)
    leaf = arena[middle.body.not_nil!.first].as(Adamas::Compiler::Frontend::ClassNode)

    enclosing.namespace_wrapper.should be_false
    outer.namespace_wrapper.should be_true
    middle.namespace_wrapper.should be_true
    outer.absolute.should be_true
    middle.absolute.should be_false
    leaf.absolute.should be_false
  end

  it "marks only outer segments of an absolute module path inside a class" do
    program = ParserNamespaceWrapperSpec.parse("class Enclosing\nmodule ::Outer::Middle::Leaf\nend\nend")
    arena = program.arena
    enclosing = arena[program.roots.first].as(Adamas::Compiler::Frontend::ClassNode)
    outer = arena[enclosing.body.not_nil!.first].as(Adamas::Compiler::Frontend::ModuleNode)
    middle = arena[outer.body.not_nil!.first].as(Adamas::Compiler::Frontend::ModuleNode)
    leaf = arena[middle.body.not_nil!.first].as(Adamas::Compiler::Frontend::ModuleNode)

    outer.namespace_wrapper.should be_true
    middle.namespace_wrapper.should be_true
    leaf.namespace_wrapper.should be_false
    outer.absolute.should be_true
    middle.absolute.should be_false
    leaf.absolute.should be_false
  end

  it "keeps a single-segment absolute module real" do
    program = ParserNamespaceWrapperSpec.parse("module ::Actual\nend")
    actual = program.arena[program.roots.first].as(Adamas::Compiler::Frontend::ModuleNode)

    actual.namespace_wrapper.should be_false
    actual.absolute.should be_true
  end
end
