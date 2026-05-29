require "spec"

require "../../src/compiler/frontend/parser"

describe "Adamas::Compiler::Frontend::Parser" do
  describe "Phase 24: Unless" do
    it "parses basic unless without else" do
      source = <<-CRYSTAL
        unless false
          x = 10
        end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      unless_node = arena[program.roots.first]
      Adamas::Compiler::Frontend.node_kind(unless_node).should eq(Adamas::Compiler::Frontend::NodeKind::Unless)

      # Check condition
      condition = arena[Adamas::Compiler::Frontend.node_condition(unless_node).not_nil!]
      Adamas::Compiler::Frontend.node_kind(condition).should eq(Adamas::Compiler::Frontend::NodeKind::Bool)
      Adamas::Compiler::Frontend.node_literal_string(condition).should eq("false")

      # Check then body
      then_body = Adamas::Compiler::Frontend.node_if_then(unless_node).not_nil!
      then_body.size.should eq(1)

      assign = arena[then_body[0]]
      Adamas::Compiler::Frontend.node_kind(assign).should eq(Adamas::Compiler::Frontend::NodeKind::Assign)
    end

    it "parses unless with else" do
      source = <<-CRYSTAL
        unless condition
          x = 10
        else
          x = 20
        end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      unless_node = arena[program.roots.first]
      Adamas::Compiler::Frontend.node_kind(unless_node).should eq(Adamas::Compiler::Frontend::NodeKind::Unless)

      # Check condition
      condition = arena[Adamas::Compiler::Frontend.node_condition(unless_node).not_nil!]
      Adamas::Compiler::Frontend.node_kind(condition).should eq(Adamas::Compiler::Frontend::NodeKind::Identifier)
      Adamas::Compiler::Frontend.node_literal_string(condition).should eq("condition")

      # Check then body (executed when condition is false)
      then_body = Adamas::Compiler::Frontend.node_if_then(unless_node).not_nil!
      then_body.size.should eq(1)

      # Check else body (executed when condition is true)
      else_body = Adamas::Compiler::Frontend.node_if_else(unless_node).not_nil!
      else_body.size.should eq(1)
    end

    it "parses unless with then keyword" do
      source = <<-CRYSTAL
        unless false then
          x = 10
        end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      unless_node = arena[program.roots.first]
      Adamas::Compiler::Frontend.node_kind(unless_node).should eq(Adamas::Compiler::Frontend::NodeKind::Unless)

      then_body = Adamas::Compiler::Frontend.node_if_then(unless_node).not_nil!
      then_body.size.should eq(1)
    end

    it "parses unless with multiple statements in then body" do
      source = <<-CRYSTAL
        unless condition
          x = 10
          y = 20
          z = 30
        end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      unless_node = arena[program.roots.first]
      Adamas::Compiler::Frontend.node_kind(unless_node).should eq(Adamas::Compiler::Frontend::NodeKind::Unless)

      then_body = Adamas::Compiler::Frontend.node_if_then(unless_node).not_nil!
      then_body.size.should eq(3)
    end

    it "parses unless with complex condition" do
      source = <<-CRYSTAL
        unless x == 10 && y == 20
          process()
        end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      unless_node = arena[program.roots.first]
      Adamas::Compiler::Frontend.node_kind(unless_node).should eq(Adamas::Compiler::Frontend::NodeKind::Unless)

      # Check condition is binary AND
      condition = arena[Adamas::Compiler::Frontend.node_condition(unless_node).not_nil!]
      Adamas::Compiler::Frontend.node_kind(condition).should eq(Adamas::Compiler::Frontend::NodeKind::Binary)
      String.new(Adamas::Compiler::Frontend.node_operator(condition).not_nil!).should eq("&&")
    end
  end
end
