require "spec"

require "../../src/compiler/frontend/parser"

describe "Adamas::Compiler::Frontend::Parser" do
  describe "Phase 81: Nil-coalescing operator (??)" do
    it "parses simple nil-coalescing" do
      source = "value ?? default"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      binary = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(binary).should eq(Adamas::Compiler::Frontend::NodeKind::Binary)
      String.new(Adamas::Compiler::Frontend.node_operator(binary).not_nil!).should eq("??")
    end

    it "parses nil-coalescing with literals" do
      source = "nil ?? 42"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      binary = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(binary).should eq(Adamas::Compiler::Frontend::NodeKind::Binary)
      String.new(Adamas::Compiler::Frontend.node_operator(binary).not_nil!).should eq("??")

      # Left side should be nil
      left = arena[Adamas::Compiler::Frontend.node_left(binary).not_nil!]
      Adamas::Compiler::Frontend.node_kind(left).should eq(Adamas::Compiler::Frontend::NodeKind::Nil)

      # Right side should be number
      right = arena[Adamas::Compiler::Frontend.node_right(binary).not_nil!]
      Adamas::Compiler::Frontend.node_kind(right).should eq(Adamas::Compiler::Frontend::NodeKind::Number)
    end

    it "parses nil-coalescing in assignment" do
      source = "name = user.name ?? \"Anonymous\""

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(assign).should eq(Adamas::Compiler::Frontend::NodeKind::Assign)

      value = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      Adamas::Compiler::Frontend.node_kind(value).should eq(Adamas::Compiler::Frontend::NodeKind::Binary)
      String.new(Adamas::Compiler::Frontend.node_operator(value).not_nil!).should eq("??")
    end

    it "parses nil-coalescing with method call" do
      source = "result = find_user() ?? create_user()"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(assign).should eq(Adamas::Compiler::Frontend::NodeKind::Assign)

      value = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      Adamas::Compiler::Frontend.node_kind(value).should eq(Adamas::Compiler::Frontend::NodeKind::Binary)
      String.new(Adamas::Compiler::Frontend.node_operator(value).not_nil!).should eq("??")

      # Both sides should be method calls
      left = arena[Adamas::Compiler::Frontend.node_left(value).not_nil!]
      Adamas::Compiler::Frontend.node_kind(left).should eq(Adamas::Compiler::Frontend::NodeKind::Call)

      right = arena[Adamas::Compiler::Frontend.node_right(value).not_nil!]
      Adamas::Compiler::Frontend.node_kind(right).should eq(Adamas::Compiler::Frontend::NodeKind::Call)
    end

    it "parses chained nil-coalescing" do
      source = "a ?? b ?? c"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      # Should parse as (a ?? b) ?? c due to left-associativity
      outer = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(outer).should eq(Adamas::Compiler::Frontend::NodeKind::Binary)
      String.new(Adamas::Compiler::Frontend.node_operator(outer).not_nil!).should eq("??")

      # Left side should be another ??
      inner = arena[Adamas::Compiler::Frontend.node_left(outer).not_nil!]
      Adamas::Compiler::Frontend.node_kind(inner).should eq(Adamas::Compiler::Frontend::NodeKind::Binary)
      String.new(Adamas::Compiler::Frontend.node_operator(inner).not_nil!).should eq("??")
    end

    it "parses nil-coalescing in if condition" do
      source = <<-CRYSTAL
      if value ?? false
        puts "yes"
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      if_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(if_node).should eq(Adamas::Compiler::Frontend::NodeKind::If)

      condition = arena[Adamas::Compiler::Frontend.node_condition(if_node).not_nil!]
      Adamas::Compiler::Frontend.node_kind(condition).should eq(Adamas::Compiler::Frontend::NodeKind::Binary)
      String.new(Adamas::Compiler::Frontend.node_operator(condition).not_nil!).should eq("??")
    end

    it "parses nil-coalescing as method argument" do
      source = "process(input ?? default_value)"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      call = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(call).should eq(Adamas::Compiler::Frontend::NodeKind::Call)

      args = Adamas::Compiler::Frontend.node_args(call).not_nil!
      args.size.should eq(1)

      arg = arena[args[0]]
      Adamas::Compiler::Frontend.node_kind(arg).should eq(Adamas::Compiler::Frontend::NodeKind::Binary)
      String.new(Adamas::Compiler::Frontend.node_operator(arg).not_nil!).should eq("??")
    end

    it "parses nil-coalescing with array/hash access" do
      source = "config[\"key\"] ?? default"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      binary = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(binary).should eq(Adamas::Compiler::Frontend::NodeKind::Binary)
      String.new(Adamas::Compiler::Frontend.node_operator(binary).not_nil!).should eq("??")

      # Left side should be index access
      left = arena[Adamas::Compiler::Frontend.node_left(binary).not_nil!]
      Adamas::Compiler::Frontend.node_kind(left).should eq(Adamas::Compiler::Frontend::NodeKind::Index)
    end

    it "disambiguates ?? from ? (ternary)" do
      source = <<-CRYSTAL
      a = b ? c : d
      e = f ?? g
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(2)
      arena = program.arena

      # First: b ? c : d (ternary)
      assign1 = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(assign1).should eq(Adamas::Compiler::Frontend::NodeKind::Assign)

      ternary = arena[Adamas::Compiler::Frontend.node_assign_value(assign1).not_nil!]
      Adamas::Compiler::Frontend.node_kind(ternary).should eq(Adamas::Compiler::Frontend::NodeKind::Ternary)

      # Second: f ?? g (nil-coalescing)
      assign2 = arena[program.roots[1]]
      Adamas::Compiler::Frontend.node_kind(assign2).should eq(Adamas::Compiler::Frontend::NodeKind::Assign)

      nil_coalesce = arena[Adamas::Compiler::Frontend.node_assign_value(assign2).not_nil!]
      Adamas::Compiler::Frontend.node_kind(nil_coalesce).should eq(Adamas::Compiler::Frontend::NodeKind::Binary)
      String.new(Adamas::Compiler::Frontend.node_operator(nil_coalesce).not_nil!).should eq("??")
    end

    it "parses nil-coalescing with complex expressions" do
      source = "(obj.method + 5) ?? default_value"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      binary = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(binary).should eq(Adamas::Compiler::Frontend::NodeKind::Binary)
      String.new(Adamas::Compiler::Frontend.node_operator(binary).not_nil!).should eq("??")

      # Left side should be grouping
      left = arena[Adamas::Compiler::Frontend.node_left(binary).not_nil!]
      Adamas::Compiler::Frontend.node_kind(left).should eq(Adamas::Compiler::Frontend::NodeKind::Grouping)
    end
  end
end
