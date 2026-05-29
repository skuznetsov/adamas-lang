require "spec"

require "../../src/compiler/frontend/parser"

describe "Adamas::Compiler::Frontend::Parser" do
  describe "Phase 75: Global variables ($var) (PRODUCTION-READY)" do
    it "parses simple global variable" do
      source = "$global_var"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      global_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(global_node).should eq(Adamas::Compiler::Frontend::NodeKind::Global)

      literal = Adamas::Compiler::Frontend.node_literal(global_node).not_nil!
      String.new(literal).should eq("$global_var")
    end

    it "parses global variable with underscores" do
      source = "$my_global_var"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      global_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(global_node).should eq(Adamas::Compiler::Frontend::NodeKind::Global)

      literal = Adamas::Compiler::Frontend.node_literal(global_node).not_nil!
      String.new(literal).should eq("$my_global_var")
    end

    it "parses global variable with question mark suffix" do
      source = "$flag?"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      global_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(global_node).should eq(Adamas::Compiler::Frontend::NodeKind::Global)

      literal = Adamas::Compiler::Frontend.node_literal(global_node).not_nil!
      String.new(literal).should eq("$flag?")
    end

    it "parses global variable with exclamation mark suffix" do
      source = "$important!"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      global_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(global_node).should eq(Adamas::Compiler::Frontend::NodeKind::Global)

      literal = Adamas::Compiler::Frontend.node_literal(global_node).not_nil!
      String.new(literal).should eq("$important!")
    end

    it "parses global variable assignment" do
      source = "$count = 42"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(assign_node).should eq(Adamas::Compiler::Frontend::NodeKind::Assign)

      target = arena[Adamas::Compiler::Frontend.node_assign_target(assign_node).not_nil!]
      Adamas::Compiler::Frontend.node_kind(target).should eq(Adamas::Compiler::Frontend::NodeKind::Global)
    end

    it "parses multiple global variables" do
      source = <<-CRYSTAL
      $first = 1
      $second = 2
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(2)
      arena = program.arena

      assign1 = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(assign1).should eq(Adamas::Compiler::Frontend::NodeKind::Assign)

      assign2 = arena[program.roots[1]]
      Adamas::Compiler::Frontend.node_kind(assign2).should eq(Adamas::Compiler::Frontend::NodeKind::Assign)
    end

    it "parses global variable in expression" do
      source = "$count + 1"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      binary = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(binary).should eq(Adamas::Compiler::Frontend::NodeKind::Binary)

      left = arena[Adamas::Compiler::Frontend.node_left(binary).not_nil!]
      Adamas::Compiler::Frontend.node_kind(left).should eq(Adamas::Compiler::Frontend::NodeKind::Global)
    end

    it "parses global variable as method argument" do
      source = "foo($global)"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      call = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(call).should eq(Adamas::Compiler::Frontend::NodeKind::Call)

      args = Adamas::Compiler::Frontend.node_args(call).not_nil!
      args.size.should eq(1)

      arg = arena[args[0]]
      Adamas::Compiler::Frontend.node_kind(arg).should eq(Adamas::Compiler::Frontend::NodeKind::Global)
    end

    it "parses global variable inside method body" do
      source = <<-CRYSTAL
      def foo
        $global_var = 42
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      method = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(method).should eq(Adamas::Compiler::Frontend::NodeKind::Def)

      body = Adamas::Compiler::Frontend.node_def_body(method).not_nil!
      body.size.should eq(1)

      assign = arena[body[0]]
      Adamas::Compiler::Frontend.node_kind(assign).should eq(Adamas::Compiler::Frontend::NodeKind::Assign)
    end

    it "parses global variable in array literal" do
      source = "[$first, $second, $third]"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      array = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(array).should eq(Adamas::Compiler::Frontend::NodeKind::ArrayLiteral)

      elements = Adamas::Compiler::Frontend.node_array_elements(array).not_nil!
      elements.size.should eq(3)

      elem1 = arena[elements[0]]
      Adamas::Compiler::Frontend.node_kind(elem1).should eq(Adamas::Compiler::Frontend::NodeKind::Global)
    end

    it "distinguishes global variable from instance variable" do
      source = "$global + @instance"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      binary = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(binary).should eq(Adamas::Compiler::Frontend::NodeKind::Binary)

      left = arena[Adamas::Compiler::Frontend.node_left(binary).not_nil!]
      Adamas::Compiler::Frontend.node_kind(left).should eq(Adamas::Compiler::Frontend::NodeKind::Global)

      right = arena[Adamas::Compiler::Frontend.node_right(binary).not_nil!]
      Adamas::Compiler::Frontend.node_kind(right).should eq(Adamas::Compiler::Frontend::NodeKind::InstanceVar)
    end

    it "parses global variable with numbers in name" do
      source = "$var123"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      global_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(global_node).should eq(Adamas::Compiler::Frontend::NodeKind::Global)

      literal = Adamas::Compiler::Frontend.node_literal(global_node).not_nil!
      String.new(literal).should eq("$var123")
    end
  end
end
