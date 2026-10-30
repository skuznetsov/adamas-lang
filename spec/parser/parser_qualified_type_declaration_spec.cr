require "spec"
require "../../src/compiler/frontend/parser"

describe "qualified enum and alias declaration names" do
  {"Owner::Level", "::Owner::Level", "::Level"}.each do |name|
    it "preserves the complete enum path #{name}" do
      source = "enum #{name} : UInt8\n  Active = 65\nend"
      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program
      parser.diagnostics.should be_empty
      node = program.arena[program.roots.first].as(Adamas::Compiler::Frontend::EnumNode)
      String.new(node.name).should eq(name)
      String.new(node.base_type.not_nil!).should eq("UInt8")
      String.new(node.members.first.name).should eq("Active")
    end

    it "preserves the complete alias path #{name}" do
      parser = Adamas::Compiler::Frontend::Parser.new(
        Adamas::Compiler::Frontend::Lexer.new("alias #{name} = Int32")
      )
      program = parser.parse_program
      parser.diagnostics.should be_empty
      node = program.arena[program.roots.first].as(Adamas::Compiler::Frontend::AliasNode)
      String.new(node.name).should eq(name)
      String.new(node.value).should eq("Int32")
    end
  end
end
