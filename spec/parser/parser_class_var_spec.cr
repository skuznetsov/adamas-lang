require "spec"

require "../../src/compiler/frontend/parser"

describe "Adamas::Compiler::Frontend::Parser" do
  describe "Phase 76: Class variables (@@var) (PRODUCTION-READY)" do
    it "parses simple class variable" do
      source = "@@class_var"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      class_var_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(class_var_node).should eq(Adamas::Compiler::Frontend::NodeKind::ClassVar)

      literal = Adamas::Compiler::Frontend.node_literal(class_var_node).not_nil!
      String.new(literal).should eq("@@class_var")
    end

    it "parses class variable with underscores" do
      source = "@@my_class_var"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      class_var_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(class_var_node).should eq(Adamas::Compiler::Frontend::NodeKind::ClassVar)

      literal = Adamas::Compiler::Frontend.node_literal(class_var_node).not_nil!
      String.new(literal).should eq("@@my_class_var")
    end

    it "parses class variable with question mark suffix" do
      source = "@@flag?"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      class_var_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(class_var_node).should eq(Adamas::Compiler::Frontend::NodeKind::ClassVar)

      literal = Adamas::Compiler::Frontend.node_literal(class_var_node).not_nil!
      String.new(literal).should eq("@@flag?")
    end

    it "parses class variable with exclamation mark suffix" do
      source = "@@important!"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      class_var_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(class_var_node).should eq(Adamas::Compiler::Frontend::NodeKind::ClassVar)

      literal = Adamas::Compiler::Frontend.node_literal(class_var_node).not_nil!
      String.new(literal).should eq("@@important!")
    end

    it "parses class variable assignment" do
      source = "@@count = 42"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(assign_node).should eq(Adamas::Compiler::Frontend::NodeKind::Assign)

      target = arena[Adamas::Compiler::Frontend.node_assign_target(assign_node).not_nil!]
      Adamas::Compiler::Frontend.node_kind(target).should eq(Adamas::Compiler::Frontend::NodeKind::ClassVar)
    end

    it "parses multiple class variables" do
      source = <<-CRYSTAL
      @@first = 1
      @@second = 2
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

    it "parses class variable in expression" do
      source = "@@count + 1"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      binary = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(binary).should eq(Adamas::Compiler::Frontend::NodeKind::Binary)

      left = arena[Adamas::Compiler::Frontend.node_left(binary).not_nil!]
      Adamas::Compiler::Frontend.node_kind(left).should eq(Adamas::Compiler::Frontend::NodeKind::ClassVar)
    end

    it "parses class variable as method argument" do
      source = "foo(@@class_var)"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      call = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(call).should eq(Adamas::Compiler::Frontend::NodeKind::Call)

      args = Adamas::Compiler::Frontend.node_args(call).not_nil!
      args.size.should eq(1)

      arg = arena[args[0]]
      Adamas::Compiler::Frontend.node_kind(arg).should eq(Adamas::Compiler::Frontend::NodeKind::ClassVar)
    end

    it "parses class variable inside class body" do
      source = <<-CRYSTAL
      class Foo
        @@class_var = 42
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      class_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(class_node).should eq(Adamas::Compiler::Frontend::NodeKind::Class)

      body = Adamas::Compiler::Frontend.node_class_body(class_node).not_nil!
      body.size.should eq(1)

      assign = arena[body[0]]
      Adamas::Compiler::Frontend.node_kind(assign).should eq(Adamas::Compiler::Frontend::NodeKind::Assign)
    end

    it "parses class variable in array literal" do
      source = "[@@first, @@second, @@third]"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      array = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(array).should eq(Adamas::Compiler::Frontend::NodeKind::ArrayLiteral)

      elements = Adamas::Compiler::Frontend.node_array_elements(array).not_nil!
      elements.size.should eq(3)

      elem1 = arena[elements[0]]
      Adamas::Compiler::Frontend.node_kind(elem1).should eq(Adamas::Compiler::Frontend::NodeKind::ClassVar)
    end

    it "distinguishes class variable from instance variable" do
      source = "@@class_var + @instance_var"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      binary = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(binary).should eq(Adamas::Compiler::Frontend::NodeKind::Binary)

      left = arena[Adamas::Compiler::Frontend.node_left(binary).not_nil!]
      Adamas::Compiler::Frontend.node_kind(left).should eq(Adamas::Compiler::Frontend::NodeKind::ClassVar)

      right = arena[Adamas::Compiler::Frontend.node_right(binary).not_nil!]
      Adamas::Compiler::Frontend.node_kind(right).should eq(Adamas::Compiler::Frontend::NodeKind::InstanceVar)
    end

    it "parses class variable with numbers in name" do
      source = "@@var123"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      class_var_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(class_var_node).should eq(Adamas::Compiler::Frontend::NodeKind::ClassVar)

      literal = Adamas::Compiler::Frontend.node_literal(class_var_node).not_nil!
      String.new(literal).should eq("@@var123")
    end

    it "distinguishes all three variable types" do
      source = "@@class_var + @instance_var + $global_var"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      # Top level (left-associative): (@@class_var + @instance_var) + $global_var
      binary1 = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(binary1).should eq(Adamas::Compiler::Frontend::NodeKind::Binary)

      # Left: (@@class_var + @instance_var)
      left1 = arena[Adamas::Compiler::Frontend.node_left(binary1).not_nil!]
      Adamas::Compiler::Frontend.node_kind(left1).should eq(Adamas::Compiler::Frontend::NodeKind::Binary)

      # Right: $global_var
      right1 = arena[Adamas::Compiler::Frontend.node_right(binary1).not_nil!]
      Adamas::Compiler::Frontend.node_kind(right1).should eq(Adamas::Compiler::Frontend::NodeKind::Global)

      # Second level: @@class_var + @instance_var
      left2 = arena[Adamas::Compiler::Frontend.node_left(left1).not_nil!]
      Adamas::Compiler::Frontend.node_kind(left2).should eq(Adamas::Compiler::Frontend::NodeKind::ClassVar)

      right2 = arena[Adamas::Compiler::Frontend.node_right(left1).not_nil!]
      Adamas::Compiler::Frontend.node_kind(right2).should eq(Adamas::Compiler::Frontend::NodeKind::InstanceVar)
    end
  end
end
