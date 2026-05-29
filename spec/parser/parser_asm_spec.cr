require "spec"

require "../../src/compiler/frontend/parser"

describe "Adamas::Compiler::Frontend::Parser" do
  describe "inline asm parsing" do
    it "parses asm with template only" do
      source = %(asm("nop"))
      parser = Adamas::Compiler::Frontend::Parser.new(
        Adamas::Compiler::Frontend::Lexer.new(source)
      )
      program = parser.parse_program

      parser.diagnostics.should be_empty
      program.roots.size.should eq(1)

      arena = program.arena
      asm_node = arena[program.roots.first].as(Adamas::Compiler::Frontend::AsmNode)
      Adamas::Compiler::Frontend.node_kind(asm_node).should eq(Adamas::Compiler::Frontend::NodeKind::Asm)

      args = Adamas::Compiler::Frontend.node_asm_args(asm_node)
      args.size.should eq(1)

      template = arena[args.first].as(Adamas::Compiler::Frontend::StringNode)
      String.new(template.value).should eq("nop")
    end

    # NOTE: This test uses invalid Crystal ASM syntax. Crystal ASM uses colons:
    #   asm("template" : outputs : inputs : clobbers : options)
    # Not comma-separated arguments like asm("add", 1, 2)
    pending "parses asm with multiple operands (INVALID SYNTAX)" do
      source = %(asm("add", 1, 2))
      parser = Adamas::Compiler::Frontend::Parser.new(
        Adamas::Compiler::Frontend::Lexer.new(source)
      )
      program = parser.parse_program

      parser.diagnostics.should be_empty
      program.roots.size.should eq(1)

      arena = program.arena
      asm_node = arena[program.roots.first].as(Adamas::Compiler::Frontend::AsmNode)
      Adamas::Compiler::Frontend.node_kind(asm_node).should eq(Adamas::Compiler::Frontend::NodeKind::Asm)

      args = Adamas::Compiler::Frontend.node_asm_args(asm_node)
      args.size.should eq(3)

      template = arena[args[0]].as(Adamas::Compiler::Frontend::StringNode)
      Adamas::Compiler::Frontend.node_kind(template).should eq(Adamas::Compiler::Frontend::NodeKind::String)
      String.new(template.value).should eq("add")

      first_operand = arena[args[1]].as(Adamas::Compiler::Frontend::NumberNode)
      Adamas::Compiler::Frontend.node_kind(first_operand).should eq(Adamas::Compiler::Frontend::NodeKind::Number)

      second_operand = arena[args[2]].as(Adamas::Compiler::Frontend::NumberNode)
      Adamas::Compiler::Frontend.node_kind(second_operand).should eq(Adamas::Compiler::Frontend::NodeKind::Number)
    end
  end
end
