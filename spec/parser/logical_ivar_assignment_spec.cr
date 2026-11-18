require "spec"
require "../../src/compiler/frontend/parser"

private def check_logical_field_write(arena, id, operator)
  read = arena[id].as(Adamas::Compiler::Frontend::BinaryNode)
  String.new(read.operator).should eq(operator)
  arena[read.left].should be_a(Adamas::Compiler::Frontend::InstanceVarNode)
  write = arena[read.right].as(Adamas::Compiler::Frontend::AssignNode)
  write.target.should eq(read.left)
  arena[write.value].should be_a(Adamas::Compiler::Frontend::NumberNode)
end

describe "short-circuit instance variable assignments" do
  ["||", "&&"].each do |operator|
    it "keeps the #{operator}= write inside both the condition and the postfix modifier" do
      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new("@value #{operator}= 65 if guard"))
      program = parser.parse_program
      parser.diagnostics.should be_empty
      conditional = program.arena[program.roots.first].as(Adamas::Compiler::Frontend::IfNode)
      check_logical_field_write(program.arena, conditional.then_body.first, operator)
    end

    it "keeps a nested #{operator}= assignment as a value" do
      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new("take(@value #{operator}= 65)"))
      program = parser.parse_program
      parser.diagnostics.should be_empty
      call = program.arena[program.roots.first].as(Adamas::Compiler::Frontend::CallNode)
      check_logical_field_write(program.arena, call.args.first, operator)
    end
  end
end
