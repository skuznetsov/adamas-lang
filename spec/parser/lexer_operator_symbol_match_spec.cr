require "spec"
require "../../src/compiler/frontend/parser"

def operator_symbol_tokens(source : String) : Array(Adamas::Compiler::Frontend::Token)
  tokens = [] of Adamas::Compiler::Frontend::Token
  Adamas::Compiler::Frontend::Lexer.new(source).each_token(skip_trivia: true) do |token|
    tokens << token
  end
  tokens
end

describe "Lexer operator-symbol longest match" do
  it "keeps :<=> whole before :<= and preserves adjacent shorter symbols" do
    source = ":<=> :<= :< :<< :>= :>"
    tokens = operator_symbol_tokens(source)
    tokens.map { |token| token.kind }.should eq([
      Adamas::Compiler::Frontend::Token::Kind::Symbol,
      Adamas::Compiler::Frontend::Token::Kind::Symbol,
      Adamas::Compiler::Frontend::Token::Kind::Symbol,
      Adamas::Compiler::Frontend::Token::Kind::Symbol,
      Adamas::Compiler::Frontend::Token::Kind::Symbol,
      Adamas::Compiler::Frontend::Token::Kind::Symbol,
      Adamas::Compiler::Frontend::Token::Kind::EOF,
    ])
    tokens[0].lexeme.should eq(":<=>")
    tokens[0].span.start_offset.should eq(0)
    tokens[0].span.end_offset.should eq(4)
    tokens[1].lexeme.should eq(":<=")
    tokens[2].lexeme.should eq(":<")
    tokens[3].lexeme.should eq(":<<")
    tokens[4].lexeme.should eq(":>=")
    tokens[5].lexeme.should eq(":>")
  end

  it "leaves trailing assignment tokens after :<< and :<=" do
    tokens = operator_symbol_tokens(":<<= :<==")

    tokens[0].lexeme.should eq(":<<")
    tokens[0].span.start_offset.should eq(0)
    tokens[0].span.end_offset.should eq(3)
    tokens[1].lexeme.should eq("=")
    tokens[1].span.start_offset.should eq(3)
    tokens[1].span.end_offset.should eq(4)
    tokens[2].lexeme.should eq(":<=")
    tokens[2].span.start_offset.should eq(5)
    tokens[2].span.end_offset.should eq(8)
    tokens[3].lexeme.should eq("=")
    tokens[3].span.start_offset.should eq(8)
    tokens[3].span.end_offset.should eq(9)
    tokens[4].kind.should eq(Adamas::Compiler::Frontend::Token::Kind::EOF)
  end

  it "builds :<=> as one symbol AST node" do
    parser = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new(":<=>")
    )
    program = parser.parse_program

    parser.diagnostics.should be_empty
    program.roots.size.should eq(1)
    symbol = program.arena[program.roots[0]]
    Adamas::Compiler::Frontend.node_kind(symbol).should eq(Adamas::Compiler::Frontend::NodeKind::Symbol)
    typed_symbol = symbol.unsafe_as(Adamas::Compiler::Frontend::SymbolNode)
    String.new(typed_symbol.name).should eq(":<=>")
    symbol.span.start_offset.should eq(0)
    symbol.span.end_offset.should eq(4)
  end
end
