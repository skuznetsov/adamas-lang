require "spec"
require "compiler/crystal/syntax"

class OriginalCFunBoundaryVisitor < Crystal::Visitor
  getter names = [] of String
  getter arities = [] of Int32
  def visit(node : Crystal::FunDef)
    @names << node.name
    @arities << node.args.size
    false
  end
  def visit(node : Crystal::ASTNode)
    true
  end
end

describe "original C callback grammar 1" do
  it "preserves declarations and outer formal boundaries" do
    visitor = OriginalCFunBoundaryVisitor.new
    Crystal::Parser.parse(File.read(File.join(__DIR__, "../fixtures/unnamed_fun_callback/grammar_1.cr"))).accept(visitor)
    visitor.names.should eq(["before", "set_callback", "after"])
    visitor.arities.should eq([1, 2, 1])
  end
end

describe "original C callback grammar 2" do
  it "preserves declarations and outer formal boundaries" do
    visitor = OriginalCFunBoundaryVisitor.new
    Crystal::Parser.parse(File.read(File.join(__DIR__, "../fixtures/unnamed_fun_callback/grammar_2.cr"))).accept(visitor)
    visitor.names.should eq(["install", "after"])
    visitor.arities.should eq([4, 0])
  end
end

describe "original C callback grammar 3" do
  it "preserves declarations and outer formal boundaries" do
    visitor = OriginalCFunBoundaryVisitor.new
    Crystal::Parser.parse(File.read(File.join(__DIR__, "../fixtures/unnamed_fun_callback/grammar_3.cr"))).accept(visitor)
    visitor.names.should eq(["install", "after"])
    visitor.arities.should eq([2, 0])
  end
end

describe "original C callback grammar 4" do
  it "preserves declarations and outer formal boundaries" do
    visitor = OriginalCFunBoundaryVisitor.new
    Crystal::Parser.parse(File.read(File.join(__DIR__, "../fixtures/unnamed_fun_callback/grammar_4.cr"))).accept(visitor)
    visitor.names.should eq(["mixed", "after"])
    visitor.arities.should eq([3, 0])
  end
end

describe "original C callback grammar 5" do
  it "preserves declarations and outer formal boundaries" do
    visitor = OriginalCFunBoundaryVisitor.new
    Crystal::Parser.parse(File.read(File.join(__DIR__, "../fixtures/unnamed_fun_callback/grammar_5.cr"))).accept(visitor)
    visitor.names.should eq(["install", "after"])
    visitor.arities.should eq([3, 0])
  end
end

describe "original C callback return grammar" do
  it "continues the type list without an outer fun parameter delimiter" do
    visitor = OriginalCFunBoundaryVisitor.new
    Crystal::Parser.parse(File.read(File.join(__DIR__, "../fixtures/unnamed_fun_callback/grammar_6.cr"))).accept(visitor)
    visitor.names.should eq(["callback", "after"])
    visitor.arities.should eq([0, 0])
  end
end
