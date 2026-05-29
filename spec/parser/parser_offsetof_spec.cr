require "spec"

require "../../src/compiler/frontend/parser"

describe "Adamas::Compiler::Frontend::Parser" do
  describe "Phase 86: Offsetof keyword (field offset in type)" do
    it "parses offsetof with type and symbol field" do
      source = "x = offsetof(Person, :name)"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(assign).should eq(Adamas::Compiler::Frontend::NodeKind::Assign)

      # Value should be offsetof
      value = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      Adamas::Compiler::Frontend.node_kind(value).should eq(Adamas::Compiler::Frontend::NodeKind::Offsetof)

      # Should have exactly 2 arguments
      args = Adamas::Compiler::Frontend.node_offsetof_args(value).not_nil!
      args.size.should eq(2)

      # First argument should be Person (identifier)
      type_arg = arena[args[0]]
      Adamas::Compiler::Frontend.node_kind(type_arg).should eq(Adamas::Compiler::Frontend::NodeKind::Identifier)
      String.new(Adamas::Compiler::Frontend.node_literal(type_arg).not_nil!).should eq("Person")

      # Second argument should be :name (symbol)
      field_arg = arena[args[1]]
      Adamas::Compiler::Frontend.node_kind(field_arg).should eq(Adamas::Compiler::Frontend::NodeKind::Symbol)
    end

    it "parses offsetof with different field name" do
      source = "offset = offsetof(MyStruct, :field)"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      value = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      Adamas::Compiler::Frontend.node_kind(value).should eq(Adamas::Compiler::Frontend::NodeKind::Offsetof)

      args = Adamas::Compiler::Frontend.node_offsetof_args(value).not_nil!
      args.size.should eq(2)

      # Type argument
      type_arg = arena[args[0]]
      Adamas::Compiler::Frontend.node_kind(type_arg).should eq(Adamas::Compiler::Frontend::NodeKind::Identifier)
      String.new(Adamas::Compiler::Frontend.node_literal(type_arg).not_nil!).should eq("MyStruct")

      # Field argument (symbol)
      field_arg = arena[args[1]]
      Adamas::Compiler::Frontend.node_kind(field_arg).should eq(Adamas::Compiler::Frontend::NodeKind::Symbol)
    end

    it "parses offsetof with generic type" do
      source = "x = offsetof(Array(Int32), :size)"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      value = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      Adamas::Compiler::Frontend.node_kind(value).should eq(Adamas::Compiler::Frontend::NodeKind::Offsetof)

      args = Adamas::Compiler::Frontend.node_offsetof_args(value).not_nil!
      args.size.should eq(2)

      # Type argument should be generic
      type_arg = arena[args[0]]
      Adamas::Compiler::Frontend.node_kind(type_arg).should eq(Adamas::Compiler::Frontend::NodeKind::Generic)

      # Field argument should be symbol
      field_arg = arena[args[1]]
      Adamas::Compiler::Frontend.node_kind(field_arg).should eq(Adamas::Compiler::Frontend::NodeKind::Symbol)
    end

    it "parses offsetof as function argument" do
      source = "puts(offsetof(Point, :x))"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      # Root should be a call
      call = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(call).should eq(Adamas::Compiler::Frontend::NodeKind::Call)

      # Argument should be offsetof
      arg = arena[Adamas::Compiler::Frontend.node_args(call).not_nil![0]]
      Adamas::Compiler::Frontend.node_kind(arg).should eq(Adamas::Compiler::Frontend::NodeKind::Offsetof)

      args = Adamas::Compiler::Frontend.node_offsetof_args(arg).not_nil!
      args.size.should eq(2)
    end

    it "parses offsetof in return statement" do
      source = "return offsetof(User, :age)"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      ret = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(ret).should eq(Adamas::Compiler::Frontend::NodeKind::Return)

      # Return value should be offsetof
      value = arena[Adamas::Compiler::Frontend.node_return_value(ret).not_nil!]
      Adamas::Compiler::Frontend.node_kind(value).should eq(Adamas::Compiler::Frontend::NodeKind::Offsetof)

      args = Adamas::Compiler::Frontend.node_offsetof_args(value).not_nil!
      args.size.should eq(2)
    end

    it "parses offsetof with namespaced type" do
      source = "x = offsetof(Foo::Bar, :field)"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      value = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      Adamas::Compiler::Frontend.node_kind(value).should eq(Adamas::Compiler::Frontend::NodeKind::Offsetof)

      args = Adamas::Compiler::Frontend.node_offsetof_args(value).not_nil!
      args.size.should eq(2)

      # Type argument should be path expression (Foo::Bar)
      type_arg = arena[args[0]]
      Adamas::Compiler::Frontend.node_kind(type_arg).should eq(Adamas::Compiler::Frontend::NodeKind::Path)
    end

    it "parses offsetof in if condition" do
      source = <<-CRYSTAL
        if offsetof(Data, :size) > 0
          puts "yes"
        end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      if_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(if_node).should eq(Adamas::Compiler::Frontend::NodeKind::If)

      # Condition should be comparison with offsetof on left
      condition = arena[Adamas::Compiler::Frontend.node_condition(if_node).not_nil!]
      Adamas::Compiler::Frontend.node_kind(condition).should eq(Adamas::Compiler::Frontend::NodeKind::Binary)

      left = arena[Adamas::Compiler::Frontend.node_left(condition).not_nil!]
      Adamas::Compiler::Frontend.node_kind(left).should eq(Adamas::Compiler::Frontend::NodeKind::Offsetof)

      args = Adamas::Compiler::Frontend.node_offsetof_args(left).not_nil!
      args.size.should eq(2)
    end

    it "parses multiple offsetof calls" do
      source = <<-CRYSTAL
        x = offsetof(A, :f1)
        y = offsetof(B, :f2)
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(2)
      arena = program.arena

      # First assignment
      assign1 = arena[program.roots[0]]
      value1 = arena[Adamas::Compiler::Frontend.node_assign_value(assign1).not_nil!]
      Adamas::Compiler::Frontend.node_kind(value1).should eq(Adamas::Compiler::Frontend::NodeKind::Offsetof)
      args1 = Adamas::Compiler::Frontend.node_offsetof_args(value1).not_nil!
      args1.size.should eq(2)

      # Second assignment
      assign2 = arena[program.roots[1]]
      value2 = arena[Adamas::Compiler::Frontend.node_assign_value(assign2).not_nil!]
      Adamas::Compiler::Frontend.node_kind(value2).should eq(Adamas::Compiler::Frontend::NodeKind::Offsetof)
      args2 = Adamas::Compiler::Frontend.node_offsetof_args(value2).not_nil!
      args2.size.should eq(2)
    end
  end
end
