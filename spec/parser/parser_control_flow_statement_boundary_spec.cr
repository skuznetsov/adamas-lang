require "spec"
require "../../src/compiler/frontend/parser"

private def parse_control_flow_boundary(source : String)
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  program
end

describe "Control-flow expression statement boundaries" do
  {
    "if"     => "if false\n0\nend",
    "unless" => "unless true\n0\nend",
    "while"  => "while false\n0\nend",
    "until"  => "until true\n0\nend",
    "begin"  => "begin\n0\nend",
    "loop"   => "loop do\nbreak\nend",
    "spawn"  => "spawn do\n0\nend",
    "select" => "select\nwhen channel.receive\n0\nend",
    "case"   => "case 0\nwhen 0\n0\nend",
  }.each do |name, expression|
    {"newline" => "\n", "semicolon" => "; "}.each do |separator_name, separator|
      it "keeps a negative statement after #{name} and a #{separator_name}" do
        program = parse_control_flow_boundary(expression + separator + "-42_i64")
        program.roots.size.should eq(2)
        tail = program.arena[program.roots.last]
        Adamas::Compiler::Frontend.node_kind(tail).should eq(Adamas::Compiler::Frontend::NodeKind::Unary)
        String.new(Adamas::Compiler::Frontend.node_operator(tail).not_nil!).should eq("-")
      end
    end
  end

  {
    "if"     => "if true\n42\nelse\n0\nend",
    "unless" => "unless false\n42\nelse\n0\nend",
    "begin"  => "begin\n42\nend",
    "case"   => "case 0\nwhen 0\n42\nend",
  }.each do |name, expression|
    it "retains same-line subtraction from #{name}" do
      program = parse_control_flow_boundary(expression + " - 2")
      program.roots.size.should eq(1)
      node = program.arena[program.roots.first]
      Adamas::Compiler::Frontend.node_kind(node).should eq(Adamas::Compiler::Frontend::NodeKind::Binary)
      String.new(Adamas::Compiler::Frontend.node_operator(node).not_nil!).should eq("-")
    end
  end

  it "retains a chained method on the next line" do
    program = parse_control_flow_boundary("if true\n42\nelse\n0\nend\n.abs")
    program.roots.size.should eq(1)
    node = program.arena[program.roots.first]
    Adamas::Compiler::Frontend.node_kind(node).should eq(Adamas::Compiler::Frontend::NodeKind::MemberAccess)
  end
end
