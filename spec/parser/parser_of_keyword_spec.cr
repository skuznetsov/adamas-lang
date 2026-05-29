require "spec"

require "../../src/compiler/frontend/parser"

describe "Adamas::Compiler::Frontend::Parser" do
  describe "Phase 91: 'of' keyword (explicit generic type specification)" do
    it "parses empty array with simple type" do
      source = <<-CRYSTAL
      [] of Int32
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      array_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(array_node).should eq(Adamas::Compiler::Frontend::NodeKind::ArrayLiteral)

      # Empty array
      elements = Adamas::Compiler::Frontend.node_array_elements(array_node)
      elements.should_not be_nil
      elements.not_nil!.should be_empty

      # Has type specification
      of_type = Adamas::Compiler::Frontend.node_array_of_type(array_node)
      of_type.should_not be_nil

      type_node = arena[of_type.not_nil!]
      Adamas::Compiler::Frontend.node_kind(type_node).should eq(Adamas::Compiler::Frontend::NodeKind::Identifier)
      String.new(Adamas::Compiler::Frontend.node_literal(type_node).not_nil!).should eq("Int32")
    end

    it "parses array with elements and simple type" do
      source = <<-CRYSTAL
      [1, 2, 3] of Int32
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      array_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(array_node).should eq(Adamas::Compiler::Frontend::NodeKind::ArrayLiteral)

      # Has 3 elements
      elements = Adamas::Compiler::Frontend.node_array_elements(array_node).not_nil!
      elements.size.should eq(3)

      # Has type specification
      of_type = Adamas::Compiler::Frontend.node_array_of_type(array_node)
      of_type.should_not be_nil

      type_node = arena[of_type.not_nil!]
      Adamas::Compiler::Frontend.node_kind(type_node).should eq(Adamas::Compiler::Frontend::NodeKind::Identifier)
      String.new(Adamas::Compiler::Frontend.node_literal(type_node).not_nil!).should eq("Int32")
    end

    it "parses array with union type" do
      source = <<-CRYSTAL
      [1, 2, 3] of Int32 | String
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      array_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(array_node).should eq(Adamas::Compiler::Frontend::NodeKind::ArrayLiteral)

      # Has 3 elements
      elements = Adamas::Compiler::Frontend.node_array_elements(array_node).not_nil!
      elements.size.should eq(3)

      # Has union type specification
      of_type = Adamas::Compiler::Frontend.node_array_of_type(array_node)
      of_type.should_not be_nil

      type_node = arena[of_type.not_nil!]
      Adamas::Compiler::Frontend.node_kind(type_node).should eq(Adamas::Compiler::Frontend::NodeKind::Binary)
      String.new(Adamas::Compiler::Frontend.node_operator(type_node).not_nil!).should eq("|")
    end

    it "parses empty array with String type" do
      source = <<-CRYSTAL
      [] of String
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      array_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(array_node).should eq(Adamas::Compiler::Frontend::NodeKind::ArrayLiteral)

      # Empty array
      Adamas::Compiler::Frontend.node_array_elements(array_node).not_nil!.should be_empty

      # Type is String
      of_type = Adamas::Compiler::Frontend.node_array_of_type(array_node).not_nil!
      type_node = arena[of_type]
      Adamas::Compiler::Frontend.node_kind(type_node).should eq(Adamas::Compiler::Frontend::NodeKind::Identifier)
      String.new(Adamas::Compiler::Frontend.node_literal(type_node).not_nil!).should eq("String")
    end

    it "parses string array with type annotation" do
      source = <<-CRYSTAL
      ["a", "b", "c"] of String
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      array_node = arena[program.roots[0]]

      # Has 3 string elements
      elements = Adamas::Compiler::Frontend.node_array_elements(array_node).not_nil!
      elements.size.should eq(3)

      # Type is String
      of_type = Adamas::Compiler::Frontend.node_array_of_type(array_node).not_nil!
      type_node = arena[of_type]
      String.new(Adamas::Compiler::Frontend.node_literal(type_node).not_nil!).should eq("String")
    end

    it "parses empty array with union type" do
      source = <<-CRYSTAL
      [] of String | Nil
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      array_node = arena[program.roots[0]]

      # Empty array
      Adamas::Compiler::Frontend.node_array_elements(array_node).not_nil!.should be_empty

      # Union type
      of_type = Adamas::Compiler::Frontend.node_array_of_type(array_node).not_nil!
      type_node = arena[of_type]
      Adamas::Compiler::Frontend.node_kind(type_node).should eq(Adamas::Compiler::Frontend::NodeKind::Binary)
      String.new(Adamas::Compiler::Frontend.node_operator(type_node).not_nil!).should eq("|")
    end

    it "parses array with generic type (Array)" do
      source = <<-CRYSTAL
      [[1], [2]] of Array(Int32)
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      array_node = arena[program.roots[0]]

      # Has 2 array elements
      elements = Adamas::Compiler::Frontend.node_array_elements(array_node).not_nil!
      elements.size.should eq(2)

      # Type is Generic (Array(Int32))
      of_type = Adamas::Compiler::Frontend.node_array_of_type(array_node).not_nil!
      type_node = arena[of_type]
      Adamas::Compiler::Frontend.node_kind(type_node).should eq(Adamas::Compiler::Frontend::NodeKind::Generic)
    end

    it "parses array of generic type with typeof argument" do
      source = <<-CRYSTAL
      [] of Tuple(typeof(Chunk.key_type(self, block)), Array(T))
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      array_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(array_node).should eq(Adamas::Compiler::Frontend::NodeKind::ArrayLiteral)

      of_type = Adamas::Compiler::Frontend.node_array_of_type(array_node).not_nil!
      generic_node = arena[of_type]
      Adamas::Compiler::Frontend.node_kind(generic_node).should eq(Adamas::Compiler::Frontend::NodeKind::Generic)

      generic_name = arena[Adamas::Compiler::Frontend.node_generic_name(generic_node).not_nil!]
      String.new(Adamas::Compiler::Frontend.node_literal(generic_name).not_nil!).should eq("Tuple")

      type_args = Adamas::Compiler::Frontend.node_generic_type_args(generic_node).not_nil!
      type_args.size.should eq(2)

      first_arg = arena[type_args[0]]
      Adamas::Compiler::Frontend.node_kind(first_arg).should eq(Adamas::Compiler::Frontend::NodeKind::Identifier)
      String.new(Adamas::Compiler::Frontend.node_literal(first_arg).not_nil!).should eq("typeof(Chunk.key_type(self, block))")

      second_arg = arena[type_args[1]]
      Adamas::Compiler::Frontend.node_kind(second_arg).should eq(Adamas::Compiler::Frontend::NodeKind::Identifier)
      String.new(Adamas::Compiler::Frontend.node_literal(second_arg).not_nil!).should eq("Array(T)")
    end

    it "parses array without 'of' clause" do
      source = <<-CRYSTAL
      [1, 2, 3]
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      array_node = arena[program.roots[0]]

      # Has 3 elements
      elements = Adamas::Compiler::Frontend.node_array_elements(array_node).not_nil!
      elements.size.should eq(3)

      # No type specification
      Adamas::Compiler::Frontend.node_array_of_type(array_node).should be_nil
    end

    it "parses 'of' in variable assignment" do
      source = <<-CRYSTAL
      x = [1, 2] of Int32
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(assign_node).should eq(Adamas::Compiler::Frontend::NodeKind::Assign)

      # Right side is array with 'of'
      array_node = arena[Adamas::Compiler::Frontend.node_assign_value(assign_node).not_nil!]
      Adamas::Compiler::Frontend.node_kind(array_node).should eq(Adamas::Compiler::Frontend::NodeKind::ArrayLiteral)

      Adamas::Compiler::Frontend.node_array_of_type(array_node).should_not be_nil
    end

    it "parses 'of' in method call argument" do
      source = <<-CRYSTAL
      foo([1, 2] of Int32)
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      call_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(call_node).should eq(Adamas::Compiler::Frontend::NodeKind::Call)

      # Argument is array with 'of'
      args = Adamas::Compiler::Frontend.node_args(call_node).not_nil!
      args.size.should eq(1)

      array_node = arena[args[0]]
      Adamas::Compiler::Frontend.node_kind(array_node).should eq(Adamas::Compiler::Frontend::NodeKind::ArrayLiteral)
      Adamas::Compiler::Frontend.node_array_of_type(array_node).should_not be_nil
    end
  end
end
