require "spec"

require "../../src/compiler/frontend/parser"

describe "Adamas::Compiler::Frontend::Parser" do
  describe "Heredoc literals" do
    it "parses a simple heredoc" do
      source = <<-CRYSTAL
      msg = <<-HERE
      hello
      world
      HERE
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(assign).should eq(Adamas::Compiler::Frontend::NodeKind::Assign)

      value = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      Adamas::Compiler::Frontend.node_kind(value).should eq(Adamas::Compiler::Frontend::NodeKind::String)
    end

    it "parses heredoc with interpolation as a string node" do
      source = <<-CRYSTAL
      name = "world"
      msg = <<-HERE
      hello \#{name}
      HERE
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(2)
      arena = program.arena

      assign = arena[program.roots[1]]
      Adamas::Compiler::Frontend.node_kind(assign).should eq(Adamas::Compiler::Frontend::NodeKind::Assign)

      value = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      Adamas::Compiler::Frontend.node_kind(value).should eq(Adamas::Compiler::Frontend::NodeKind::StringInterpolation)
      pieces = value.as(Adamas::Compiler::Frontend::StringInterpolationNode).pieces
      pieces.map(&.kind).should eq([
        Adamas::Compiler::Frontend::StringPiece::Kind::Text,
        Adamas::Compiler::Frontend::StringPiece::Kind::Expression,
      ])
      pieces[0].text.should eq("hello ")
    end

    it "decodes heredoc bodies like Crystal" do
      # Each line loses the closing delimiter's indentation, the line break
      # before the closing delimiter is not content, and a non-raw body
      # decodes escapes.
      cases = [
        {"s = <<-T\n  a\\tb\n  T\n", "a\tb"},
        {"s = <<-T\n    a\n  b\n\n  T\n", "  a\nb\n"},
        {"s = <<-'T'\n  a\\tb\n  T\n", "a\\tb"},
        {"s = <<-T\n  T\n", ""},
        {"s = <<-T\nabc\nT\n", "abc"},
        {"s = <<-T\n  %(ab)\n  T\n", "%(ab)"},
        {"s = <<-T\n  a\\n\n  T\n", "a\n"},
        {"s = <<-T\r\n  a\r\n  b\r\n  T\r\n", "a\r\nb"},
        {"s = <<-T\n  a \\\n    b\n  T\n", "a b"},
        {"s = <<-T\n  a\n \n  b\n  T\n", "a\n\nb"},
      ]

      cases.each do |test_case|
        parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(test_case[0]))
        program = parser.parse_program

        parser.diagnostics.should be_empty
        program.roots.size.should eq(1)
        assign = program.arena[program.roots[0]]
        value = program.arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
        Adamas::Compiler::Frontend.node_kind(value).should eq(Adamas::Compiler::Frontend::NodeKind::String)
        String.new(Adamas::Compiler::Frontend.node_literal(value).not_nil!).should eq(test_case[1])
      end
    end

    it "decodes each heredoc body of one opener line" do
      source = "f(<<-A, <<-B)\n  xy\n  A\n    pqr\n    B\n"
      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      parser.diagnostics.should be_empty
      call = program.arena[program.roots[0]]
      args = call.as(Adamas::Compiler::Frontend::CallNode).args
      args.map { |arg| String.new(Adamas::Compiler::Frontend.node_literal(program.arena[arg]).not_nil!) }.should eq(["xy", "pqr"])
    end

    it "keeps interpolated heredoc text dedented around the expression" do
      source = "x = 1\ns = <<-T\n    a\\t\#{x}\n  b\n  T\n"
      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      parser.diagnostics.should be_empty
      assign = program.arena[program.roots[1]]
      value = program.arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      pieces = value.as(Adamas::Compiler::Frontend::StringInterpolationNode).pieces
      pieces.map(&.text).should eq(["  a\t", nil, "\nb"])
    end
  end
end
