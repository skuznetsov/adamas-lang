require "spec"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/parser"

private def parse_shorthand_outer_boundary(source : String)
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  program.roots.size.should eq(1)
  arena = program.arena.as(Adamas::Compiler::Frontend::AstArena)
  {arena, arena[program.roots.first]}
end

private def shorthand_outer_binary_operator(source : String, operator : String)
  arena, root = parse_shorthand_outer_boundary(source)
  binary = root.as(Adamas::Compiler::Frontend::BinaryNode)
  String.new(binary.operator).should eq(operator)
  call = arena[binary.left].as(Adamas::Compiler::Frontend::CallNode)
  arena[call.args.last].should be_a(Adamas::Compiler::Frontend::BlockNode)
end

describe "block shorthand outer expression boundary" do
  it "leaves logical or outside the shorthand" do
    shorthand_outer_binary_operator("obj.try &.to_i? || 0\n", "||")
  end
  it "leaves logical and outside the shorthand" do
    shorthand_outer_binary_operator("obj.try &.ready? && enabled\n", "&&")
  end
  it "leaves equality outside the shorthand" do
    shorthand_outer_binary_operator("obj.try &.value == expected\n", "==")
  end
  it "leaves a ternary outside the shorthand" do
    _, root = parse_shorthand_outer_boundary("obj.try &.ready? ? yes : no\n")
    root.should be_a(Adamas::Compiler::Frontend::TernaryNode)
  end
  it "leaves a postfix condition outside the shorthand" do
    _, root = parse_shorthand_outer_boundary("obj.try &.ready? if enabled\n")
    root.should be_a(Adamas::Compiler::Frontend::IfNode)
  end
  it "parses the actual LavinMQ named tuple boundary" do
    _, root = parse_shorthand_outer_boundary(%({"priority": options["priority"]?.try &.to_i? || 0}\n))
    root.should be_a(Adamas::Compiler::Frontend::NamedTupleLiteralNode)
  end
  it "retains an adjacent unary negative argument" do
    arena, root = parse_shorthand_outer_boundary("obj.try &.add -1\n")
    call = root.as(Adamas::Compiler::Frontend::CallNode)
    block = arena[call.args.last].as(Adamas::Compiler::Frontend::BlockNode)
    body = arena[block.body.first].as(Adamas::Compiler::Frontend::CallNode)
    body.args.size.should eq(1)
    arena[body.args.first].as(Adamas::Compiler::Frontend::NumberNode).parsed_int.should eq(-1_i64)
  end
  it "retains an ordinary no-parentheses argument" do
    arena, root = parse_shorthand_outer_boundary("obj.try &.add 1\n")
    call = root.as(Adamas::Compiler::Frontend::CallNode)
    block = arena[call.args.last].as(Adamas::Compiler::Frontend::BlockNode)
    body = arena[block.body.first].as(Adamas::Compiler::Frontend::CallNode)
    body.args.size.should eq(1)
  end
  it "retains a parenthesized shorthand call" do
    arena, root = parse_shorthand_outer_boundary("obj.try(&.add(1))\n")
    call = root.as(Adamas::Compiler::Frontend::CallNode)
    block = arena[call.args.last].as(Adamas::Compiler::Frontend::BlockNode)
    body = arena[block.body.first].as(Adamas::Compiler::Frontend::CallNode)
    body.args.size.should eq(1)
  end
end
