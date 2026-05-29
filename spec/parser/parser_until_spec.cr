require "spec"

require "../../src/compiler/frontend/parser"

describe "Adamas::Compiler::Frontend::Parser" do
  describe "Phase 25: Until" do
    it "parses basic until loop" do
      source = <<-CRYSTAL
        until false
          x = 10
        end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      until_node = arena[program.roots.first]
      Adamas::Compiler::Frontend.node_kind(until_node).should eq(Adamas::Compiler::Frontend::NodeKind::Until)

      # Check condition
      condition = arena[Adamas::Compiler::Frontend.node_condition(until_node).not_nil!]
      Adamas::Compiler::Frontend.node_kind(condition).should eq(Adamas::Compiler::Frontend::NodeKind::Bool)
      Adamas::Compiler::Frontend.node_literal_string(condition).should eq("false")

      # Check body
      body = Adamas::Compiler::Frontend.node_while_body(until_node).not_nil!
      body.size.should eq(1)

      assign = arena[body[0]]
      Adamas::Compiler::Frontend.node_kind(assign).should eq(Adamas::Compiler::Frontend::NodeKind::Assign)
    end

    it "parses until with empty body" do
      source = <<-CRYSTAL
        until true
        end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      until_node = arena[program.roots.first]
      Adamas::Compiler::Frontend.node_kind(until_node).should eq(Adamas::Compiler::Frontend::NodeKind::Until)

      # Check condition is Bool
      condition = arena[Adamas::Compiler::Frontend.node_condition(until_node).not_nil!]
      Adamas::Compiler::Frontend.node_kind(condition).should eq(Adamas::Compiler::Frontend::NodeKind::Bool)
      Adamas::Compiler::Frontend.node_literal_string(condition).should eq("true")

      body = Adamas::Compiler::Frontend.node_while_body(until_node).not_nil!
      body.size.should eq(0)
    end

    it "parses until with multiple statements" do
      source = <<-CRYSTAL
        until x == 10
          x = x + 1
          y = y + 2
          z = z + 3
        end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      until_node = arena[program.roots.first]
      Adamas::Compiler::Frontend.node_kind(until_node).should eq(Adamas::Compiler::Frontend::NodeKind::Until)

      body = Adamas::Compiler::Frontend.node_while_body(until_node).not_nil!
      body.size.should eq(3)
    end

    it "parses until with complex condition" do
      source = <<-CRYSTAL
        until x > 10 && y < 20
          process()
        end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      until_node = arena[program.roots.first]
      Adamas::Compiler::Frontend.node_kind(until_node).should eq(Adamas::Compiler::Frontend::NodeKind::Until)

      # Check condition is binary AND
      condition = arena[Adamas::Compiler::Frontend.node_condition(until_node).not_nil!]
      Adamas::Compiler::Frontend.node_kind(condition).should eq(Adamas::Compiler::Frontend::NodeKind::Binary)
      String.new(Adamas::Compiler::Frontend.node_operator(condition).not_nil!).should eq("&&")
    end

    it "parses until with break inside" do
      source = <<-CRYSTAL
        until false
          break
        end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      until_node = arena[program.roots.first]
      Adamas::Compiler::Frontend.node_kind(until_node).should eq(Adamas::Compiler::Frontend::NodeKind::Until)

      body = Adamas::Compiler::Frontend.node_while_body(until_node).not_nil!
      body.size.should eq(1)

      # Body contains break statement
      break_node = arena[body[0]]
      Adamas::Compiler::Frontend.node_kind(break_node).should eq(Adamas::Compiler::Frontend::NodeKind::Break)
    end
  end
end
