require "spec"

require "../../src/compiler/frontend/parser"

describe "Adamas::Compiler::Frontend::Parser" do
  describe "Phase 60: Generic type instantiation (PRODUCTION-READY)" do
    it "parses simple generic Box(Int32)" do
      source = "x = Box(Int32)"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(assign).should eq(Adamas::Compiler::Frontend::NodeKind::Assign)

      # Value is Generic node
      generic = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      Adamas::Compiler::Frontend.node_kind(generic).should eq(Adamas::Compiler::Frontend::NodeKind::Generic)

      # Check base type name
      name = arena[Adamas::Compiler::Frontend.node_generic_name(generic).not_nil!]
      Adamas::Compiler::Frontend.node_kind(name).should eq(Adamas::Compiler::Frontend::NodeKind::Identifier)
      String.new(Adamas::Compiler::Frontend.node_literal(name).not_nil!).should eq("Box")

      # Check type arguments
      type_args = Adamas::Compiler::Frontend.node_generic_type_args(generic).not_nil!
      type_args.size.should eq(1)

      type_arg = arena[type_args[0]]
      Adamas::Compiler::Frontend.node_kind(type_arg).should eq(Adamas::Compiler::Frontend::NodeKind::Identifier)
      String.new(Adamas::Compiler::Frontend.node_literal(type_arg).not_nil!).should eq("Int32")
    end

    it "parses generic with multiple type arguments Hash(String, Int32)" do
      source = "x = Hash(String, Int32)"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      generic = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      Adamas::Compiler::Frontend.node_kind(generic).should eq(Adamas::Compiler::Frontend::NodeKind::Generic)

      # Check base type name
      name = arena[Adamas::Compiler::Frontend.node_generic_name(generic).not_nil!]
      String.new(Adamas::Compiler::Frontend.node_literal(name).not_nil!).should eq("Hash")

      # Check type arguments
      type_args = Adamas::Compiler::Frontend.node_generic_type_args(generic).not_nil!
      type_args.size.should eq(2)

      type_arg1 = arena[type_args[0]]
      String.new(Adamas::Compiler::Frontend.node_literal(type_arg1).not_nil!).should eq("String")

      type_arg2 = arena[type_args[1]]
      String.new(Adamas::Compiler::Frontend.node_literal(type_arg2).not_nil!).should eq("Int32")
    end

    it "parses Array(String)" do
      source = "arr = Array(String)"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      generic = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]

      name = arena[Adamas::Compiler::Frontend.node_generic_name(generic).not_nil!]
      String.new(Adamas::Compiler::Frontend.node_literal(name).not_nil!).should eq("Array")

      type_args = Adamas::Compiler::Frontend.node_generic_type_args(generic).not_nil!
      type_args.size.should eq(1)
      type_arg = arena[type_args[0]]
      String.new(Adamas::Compiler::Frontend.node_literal(type_arg).not_nil!).should eq("String")
    end

    it "parses generic in method call" do
      source = "create(Box(Int32))"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      call = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(call).should eq(Adamas::Compiler::Frontend::NodeKind::Call)

      args = Adamas::Compiler::Frontend.node_args(call).not_nil!
      args.size.should eq(1)

      # Argument is generic
      generic = arena[args[0]]
      Adamas::Compiler::Frontend.node_kind(generic).should eq(Adamas::Compiler::Frontend::NodeKind::Generic)

      name = arena[Adamas::Compiler::Frontend.node_generic_name(generic).not_nil!]
      String.new(Adamas::Compiler::Frontend.node_literal(name).not_nil!).should eq("Box")
    end

    it "parses generic in array literal" do
      source = "[Array(Int32), Array(String)]"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      array = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(array).should eq(Adamas::Compiler::Frontend::NodeKind::ArrayLiteral)

      elements = Adamas::Compiler::Frontend.node_array_elements(array).not_nil!
      elements.size.should eq(2)

      # First element: Array(Int32)
      generic1 = arena[elements[0]]
      Adamas::Compiler::Frontend.node_kind(generic1).should eq(Adamas::Compiler::Frontend::NodeKind::Generic)

      # Second element: Array(String)
      generic2 = arena[elements[1]]
      Adamas::Compiler::Frontend.node_kind(generic2).should eq(Adamas::Compiler::Frontend::NodeKind::Generic)
    end

    it "parses triple type arguments" do
      source = "x = Triple(Int32, String, Bool)"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      generic = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]

      type_args = Adamas::Compiler::Frontend.node_generic_type_args(generic).not_nil!
      type_args.size.should eq(3)

      String.new(Adamas::Compiler::Frontend.node_literal(arena[type_args[0]]).not_nil!).should eq("Int32")
      String.new(Adamas::Compiler::Frontend.node_literal(arena[type_args[1]]).not_nil!).should eq("String")
      String.new(Adamas::Compiler::Frontend.node_literal(arena[type_args[2]]).not_nil!).should eq("Bool")
    end

    it "does not parse lowercase identifier with parens as generic" do
      source = "x = foo(42)"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]

      # Should be a Call, not Generic
      value = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      Adamas::Compiler::Frontend.node_kind(value).should eq(Adamas::Compiler::Frontend::NodeKind::Call)
      Adamas::Compiler::Frontend.node_kind(value).should_not eq(Adamas::Compiler::Frontend::NodeKind::Generic)
    end

    it "parses generic with single type argument" do
      source = "x = Pointer(UInt8)"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      generic = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      Adamas::Compiler::Frontend.node_kind(generic).should eq(Adamas::Compiler::Frontend::NodeKind::Generic)

      name = arena[Adamas::Compiler::Frontend.node_generic_name(generic).not_nil!]
      String.new(Adamas::Compiler::Frontend.node_literal(name).not_nil!).should eq("Pointer")

      type_args = Adamas::Compiler::Frontend.node_generic_type_args(generic).not_nil!
      type_args.size.should eq(1)
      type_arg = arena[type_args[0]]
      String.new(Adamas::Compiler::Frontend.node_literal(type_arg).not_nil!).should eq("UInt8")
    end

    it "parses multiple generics in statement" do
      source = <<-CRYSTAL
      a = Box(Int32)
      b = Array(String)
      c = Hash(Symbol, Float64)
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(3)
      arena = program.arena

      # Check all three are Generic
      (0..2).each do |i|
        assign = arena[program.roots[i]]
        generic = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
        Adamas::Compiler::Frontend.node_kind(generic).should eq(Adamas::Compiler::Frontend::NodeKind::Generic)
      end
    end
  end
end
