require "spec"

require "../../src/compiler/frontend/parser"

describe "Adamas::Compiler::Frontend::Parser" do
  describe "Phase 94: responds_to? keyword (method check pseudo-method)" do
    it "parses simple responds_to? check with symbol" do
      source = <<-CRYSTAL
      result = obj.responds_to?(:to_s)
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(assign_node).should eq(Adamas::Compiler::Frontend::NodeKind::Assign)

      # Right side is RespondsTo node
      responds_to_node = arena[Adamas::Compiler::Frontend.node_assign_value(assign_node).not_nil!]
      Adamas::Compiler::Frontend.node_kind(responds_to_node).should eq(Adamas::Compiler::Frontend::NodeKind::RespondsTo)

      # Check receiver (obj)
      receiver = arena[responds_to_node.as(Adamas::Compiler::Frontend::RespondsToNode).expression]
      Adamas::Compiler::Frontend.node_kind(receiver).should eq(Adamas::Compiler::Frontend::NodeKind::Identifier)
      String.new(Adamas::Compiler::Frontend.node_literal(receiver).not_nil!).should eq("obj")

      # Check method name (symbol :to_s)
      method_name = arena[responds_to_node.as(Adamas::Compiler::Frontend::RespondsToNode).method_name]
      Adamas::Compiler::Frontend.node_kind(method_name).should eq(Adamas::Compiler::Frontend::NodeKind::Symbol)
    end

    it "parses responds_to? with string argument" do
      source = <<-CRYSTAL
      obj.responds_to?("method_name")
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      responds_to_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(responds_to_node).should eq(Adamas::Compiler::Frontend::NodeKind::RespondsTo)

      # Check method name is string
      method_name = arena[responds_to_node.as(Adamas::Compiler::Frontend::RespondsToNode).method_name]
      Adamas::Compiler::Frontend.node_kind(method_name).should eq(Adamas::Compiler::Frontend::NodeKind::String)
    end

    it "parses responds_to? in conditional" do
      source = <<-CRYSTAL
      if obj.responds_to?(:foo)
        obj.foo
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      if_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(if_node).should eq(Adamas::Compiler::Frontend::NodeKind::If)

      # Condition is responds_to?
      condition = arena[Adamas::Compiler::Frontend.node_condition(if_node).not_nil!]
      Adamas::Compiler::Frontend.node_kind(condition).should eq(Adamas::Compiler::Frontend::NodeKind::RespondsTo)
    end

    it "parses chained responds_to? calls" do
      source = <<-CRYSTAL
      obj.foo.responds_to?(:bar)
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      responds_to_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(responds_to_node).should eq(Adamas::Compiler::Frontend::NodeKind::RespondsTo)

      # Receiver should be member access (obj.foo)
      receiver = arena[responds_to_node.as(Adamas::Compiler::Frontend::RespondsToNode).expression]
      Adamas::Compiler::Frontend.node_kind(receiver).should eq(Adamas::Compiler::Frontend::NodeKind::MemberAccess)
    end

    it "parses responds_to? in method call arguments" do
      source = <<-CRYSTAL
      puts(obj.responds_to?(:to_s))
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      call_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(call_node).should eq(Adamas::Compiler::Frontend::NodeKind::Call)

      # Argument is responds_to?
      args = Adamas::Compiler::Frontend.node_args(call_node).not_nil!
      args.size.should eq(1)

      arg = arena[args[0]]
      Adamas::Compiler::Frontend.node_kind(arg).should eq(Adamas::Compiler::Frontend::NodeKind::RespondsTo)
    end

    it "parses responds_to? in array literal" do
      source = <<-CRYSTAL
      [a.responds_to?(:x), b.responds_to?(:y)]
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      array_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(array_node).should eq(Adamas::Compiler::Frontend::NodeKind::ArrayLiteral)

      elements = Adamas::Compiler::Frontend.node_array_elements(array_node).not_nil!
      elements.size.should eq(2)

      # Both elements are responds_to?
      first = arena[elements[0]]
      Adamas::Compiler::Frontend.node_kind(first).should eq(Adamas::Compiler::Frontend::NodeKind::RespondsTo)

      second = arena[elements[1]]
      Adamas::Compiler::Frontend.node_kind(second).should eq(Adamas::Compiler::Frontend::NodeKind::RespondsTo)
    end

    it "parses responds_to? in binary expression" do
      source = <<-CRYSTAL
      a.responds_to?(:foo) && b.responds_to?(:bar)
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      binary_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(binary_node).should eq(Adamas::Compiler::Frontend::NodeKind::Binary)
      String.new(Adamas::Compiler::Frontend.node_operator(binary_node).not_nil!).should eq("&&")

      # Left side is responds_to?
      left = arena[Adamas::Compiler::Frontend.node_left(binary_node).not_nil!]
      Adamas::Compiler::Frontend.node_kind(left).should eq(Adamas::Compiler::Frontend::NodeKind::RespondsTo)

      # Right side is responds_to?
      right = arena[Adamas::Compiler::Frontend.node_right(binary_node).not_nil!]
      Adamas::Compiler::Frontend.node_kind(right).should eq(Adamas::Compiler::Frontend::NodeKind::RespondsTo)
    end

    it "parses responds_to? in return statement" do
      source = <<-CRYSTAL
      def check
        return obj.responds_to?(:method)
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      method_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(method_node).should eq(Adamas::Compiler::Frontend::NodeKind::Def)

      def_body = Adamas::Compiler::Frontend.node_def_body(method_node).not_nil!
      def_body.size.should eq(1)
      body = arena[def_body[0]]
      Adamas::Compiler::Frontend.node_kind(body).should eq(Adamas::Compiler::Frontend::NodeKind::Return)

      return_value = arena[Adamas::Compiler::Frontend.node_return_value(body).not_nil!]
      Adamas::Compiler::Frontend.node_kind(return_value).should eq(Adamas::Compiler::Frontend::NodeKind::RespondsTo)
    end

    it "parses responds_to? with instance variable" do
      source = <<-CRYSTAL
      @obj.responds_to?(:size)
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      responds_to_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(responds_to_node).should eq(Adamas::Compiler::Frontend::NodeKind::RespondsTo)

      # Receiver is instance variable
      receiver = arena[responds_to_node.as(Adamas::Compiler::Frontend::RespondsToNode).expression]
      Adamas::Compiler::Frontend.node_kind(receiver).should eq(Adamas::Compiler::Frontend::NodeKind::InstanceVar)
    end

    it "parses responds_to? in unless statement" do
      source = <<-CRYSTAL
      unless obj.responds_to?(:method)
        puts "missing"
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      unless_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(unless_node).should eq(Adamas::Compiler::Frontend::NodeKind::Unless)

      # Condition is responds_to? (Unless reuses if_condition field)
      condition = arena[Adamas::Compiler::Frontend.node_condition(unless_node).not_nil!]
      Adamas::Compiler::Frontend.node_kind(condition).should eq(Adamas::Compiler::Frontend::NodeKind::RespondsTo)
    end

    it "parses responds_to? in ternary expression" do
      source = <<-CRYSTAL
      obj.responds_to?(:foo) ? obj.foo : nil
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      ternary_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(ternary_node).should eq(Adamas::Compiler::Frontend::NodeKind::Ternary)

      # Condition is responds_to?
      condition = arena[Adamas::Compiler::Frontend.node_ternary_condition(ternary_node).not_nil!]
      Adamas::Compiler::Frontend.node_kind(condition).should eq(Adamas::Compiler::Frontend::NodeKind::RespondsTo)
    end

    it "parses nested responds_to? calls" do
      source = <<-CRYSTAL
      class Foo
        def check
          @obj.responds_to?(:bar)
        end
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      class_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(class_node).should eq(Adamas::Compiler::Frontend::NodeKind::Class)

      class_body = Adamas::Compiler::Frontend.node_class_body(class_node).not_nil!
      class_body.size.should eq(1)
      method = arena[class_body[0]]
      Adamas::Compiler::Frontend.node_kind(method).should eq(Adamas::Compiler::Frontend::NodeKind::Def)

      method_def_body = Adamas::Compiler::Frontend.node_def_body(method).not_nil!
      method_def_body.size.should eq(1)
      def_body = arena[method_def_body[0]]
      Adamas::Compiler::Frontend.node_kind(def_body).should eq(Adamas::Compiler::Frontend::NodeKind::RespondsTo)
    end
  end
end
