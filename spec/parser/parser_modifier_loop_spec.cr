require "spec"

require "../../src/compiler/frontend/parser"

describe "Adamas::Compiler::Frontend::Parser" do
  describe "Phase 27: Modifier while/until" do
    it "parses postfix while modifier" do
      source = <<-CRYSTAL
        process() while has_more
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      # Root should be a while node
      while_node = arena[program.roots.first]
      Adamas::Compiler::Frontend.node_kind(while_node).should eq(Adamas::Compiler::Frontend::NodeKind::While)

      # Condition should be identifier "has_more"
      condition = arena[Adamas::Compiler::Frontend.node_condition(while_node).not_nil!]
      Adamas::Compiler::Frontend.node_kind(condition).should eq(Adamas::Compiler::Frontend::NodeKind::Identifier)
      Adamas::Compiler::Frontend.node_literal_string(condition).should eq("has_more")

      # Body should contain the call
      body = Adamas::Compiler::Frontend.node_while_body(while_node).not_nil!
      body.size.should eq(1)

      call = arena[body[0]]
      Adamas::Compiler::Frontend.node_kind(call).should eq(Adamas::Compiler::Frontend::NodeKind::Call)
    end

    it "parses postfix until modifier" do
      source = <<-CRYSTAL
        wait() until ready
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      # Root should be an until node
      until_node = arena[program.roots.first]
      Adamas::Compiler::Frontend.node_kind(until_node).should eq(Adamas::Compiler::Frontend::NodeKind::Until)

      # Condition should be identifier "ready"
      condition = arena[Adamas::Compiler::Frontend.node_condition(until_node).not_nil!]
      Adamas::Compiler::Frontend.node_kind(condition).should eq(Adamas::Compiler::Frontend::NodeKind::Identifier)
      Adamas::Compiler::Frontend.node_literal_string(condition).should eq("ready")

      # Body should contain the call
      body = Adamas::Compiler::Frontend.node_while_body(until_node).not_nil!
      body.size.should eq(1)

      call = arena[body[0]]
      Adamas::Compiler::Frontend.node_kind(call).should eq(Adamas::Compiler::Frontend::NodeKind::Call)
    end

    it "parses postfix while with assignment" do
      source = <<-CRYSTAL
        x = x + 1 while x < 10
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      while_node = arena[program.roots.first]
      Adamas::Compiler::Frontend.node_kind(while_node).should eq(Adamas::Compiler::Frontend::NodeKind::While)

      # Body should be assignment
      body = Adamas::Compiler::Frontend.node_while_body(while_node).not_nil!
      body.size.should eq(1)

      assign = arena[body[0]]
      Adamas::Compiler::Frontend.node_kind(assign).should eq(Adamas::Compiler::Frontend::NodeKind::Assign)
    end

    it "parses postfix until with assignment" do
      source = <<-CRYSTAL
        x = x - 1 until x == 0
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      until_node = arena[program.roots.first]
      Adamas::Compiler::Frontend.node_kind(until_node).should eq(Adamas::Compiler::Frontend::NodeKind::Until)

      # Body should be assignment
      body = Adamas::Compiler::Frontend.node_while_body(until_node).not_nil!
      body.size.should eq(1)

      assign = arena[body[0]]
      Adamas::Compiler::Frontend.node_kind(assign).should eq(Adamas::Compiler::Frontend::NodeKind::Assign)
    end

    it "parses postfix while with complex condition" do
      source = <<-CRYSTAL
        process() while x > 0 && y < 100
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      while_node = arena[program.roots.first]
      Adamas::Compiler::Frontend.node_kind(while_node).should eq(Adamas::Compiler::Frontend::NodeKind::While)

      # Condition should be binary AND
      condition = arena[Adamas::Compiler::Frontend.node_condition(while_node).not_nil!]
      Adamas::Compiler::Frontend.node_kind(condition).should eq(Adamas::Compiler::Frontend::NodeKind::Binary)
      String.new(Adamas::Compiler::Frontend.node_operator(condition).not_nil!).should eq("&&")
    end

    it "handles statement without modifier loop" do
      source = <<-CRYSTAL
        process()
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      # Should be plain call, not wrapped in while/until
      call = arena[program.roots.first]
      Adamas::Compiler::Frontend.node_kind(call).should eq(Adamas::Compiler::Frontend::NodeKind::Call)
    end
  end
end
