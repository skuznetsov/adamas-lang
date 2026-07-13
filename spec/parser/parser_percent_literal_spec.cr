require "spec"

require "../../src/compiler/frontend/parser"

describe "Adamas::Compiler::Frontend::Lexer percent literals" do
  it "preserves the source slice and token kind for string and array forms" do
    cases = [
      {"%(bar)", Adamas::Compiler::Frontend::Token::Kind::String},
      {"%q(foo)", Adamas::Compiler::Frontend::Token::Kind::String},
      {"%Q(foo)", Adamas::Compiler::Frontend::Token::Kind::String},
      {"%w(one two)", Adamas::Compiler::Frontend::Token::Kind::LBracket},
      {"%i(one two)", Adamas::Compiler::Frontend::Token::Kind::LBracket},
    ]

    cases.each do |test_case|
      source = test_case[0]
      token = Adamas::Compiler::Frontend::Lexer.new(source).next_token
      token.kind.should eq(test_case[1])
      token.slice.size.should eq(source.bytesize)
      token.lexeme.should eq(source)
    end
  end

  it "keeps lowercase %q non-interpolating and uppercase %Q interpolating" do
    lower = Adamas::Compiler::Frontend::Lexer.new("%q(\#{name})").next_token
    lower.kind.should eq(Adamas::Compiler::Frontend::Token::Kind::String)

    upper = Adamas::Compiler::Frontend::Lexer.new("%Q(\#{name})").next_token
    upper.kind.should eq(Adamas::Compiler::Frontend::Token::Kind::StringInterpolation)
  end
end

describe "Adamas::Compiler::Frontend::Parser percent literals" do
  it "parses a %w word array as an ArrayLiteral node" do
    source = "%w(one two three)"
    parser = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new(source)
    )
    program = parser.parse_program

    program.roots.size.should eq(1)
    arena = program.arena
    array_node = arena[program.roots[0]]
    Adamas::Compiler::Frontend.node_kind(array_node).should eq(
      Adamas::Compiler::Frontend::NodeKind::ArrayLiteral
    )

    array_elements = Adamas::Compiler::Frontend.node_array_elements(array_node).not_nil!
    array_elements.size.should eq(3)
    array_elements.each_with_index do |element_id, index|
      element = arena[element_id]
      Adamas::Compiler::Frontend.node_kind(element).should eq(
        Adamas::Compiler::Frontend::NodeKind::String
      )
      literal = Adamas::Compiler::Frontend.node_literal(element).not_nil!
      String.new(literal).should eq(["one", "two", "three"][index])
    end
  end

  it "parses a %w word array inside macro control syntax" do
    source = <<-CRYSTAL
      macro m
        {% x = %w(one two) %}
      end
    CRYSTAL

    parser = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new(source)
    )
    program = parser.parse_program

    parser.diagnostics.should be_empty
    program.roots.size.should eq(1)
    arena = program.arena
    Adamas::Compiler::Frontend.node_kind(arena[program.roots[0]]).should eq(
      Adamas::Compiler::Frontend::NodeKind::MacroDef
    )
  end
end
