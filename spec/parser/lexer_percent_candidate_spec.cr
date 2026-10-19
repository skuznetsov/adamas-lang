require "spec"
require "../../src/compiler/frontend/parser"

def percent_candidate_tokens(source : String) : Array(Adamas::Compiler::Frontend::Token)
  tokens = [] of Adamas::Compiler::Frontend::Token
  Adamas::Compiler::Frontend::Lexer.new(source).each_token(skip_trivia: true) do |token|
    tokens << token
  end
  tokens
end

describe "Lexer percent candidate lookahead" do
  it "preserves every supported percent-literal opener and paired delimiter" do
    delimiters = [{"(", ")"}, {"[", "]"}, {"{", "}"}, {"<", ">"}, {"|", "|"}]
    delimiters.each do |pair|
      opening = pair[0]
      closing = pair[1]
      cases = [
        {"%" + opening + "body" + closing, Adamas::Compiler::Frontend::Token::Kind::String},
        {"%q" + opening + "body" + closing, Adamas::Compiler::Frontend::Token::Kind::String},
        {"%Q" + opening + "body" + closing, Adamas::Compiler::Frontend::Token::Kind::String},
        {"%r" + opening + "body" + closing, Adamas::Compiler::Frontend::Token::Kind::Regex},
        {"%w" + opening + "body" + closing, Adamas::Compiler::Frontend::Token::Kind::LBracket},
        {"%i" + opening + "body" + closing, Adamas::Compiler::Frontend::Token::Kind::LBracket},
      ]

      cases.each do |test_case|
        source = test_case[0]
        token = Adamas::Compiler::Frontend::Lexer.new(source).next_token
        token.kind.should eq(test_case[1])
        token.span.start_offset.should eq(0)
        token.span.end_offset.should eq(source.bytesize)
      end
    end
  end

  it "leaves modulo-followed identifiers and source positions intact after failed lookahead" do
    {"i", "q", "Q", "r", "w", "x"}.each do |identifier|
      source = "left%" + identifier + " + right"
      tokens = percent_candidate_tokens(source)
      tokens.map { |token| token.kind }.should eq([
        Adamas::Compiler::Frontend::Token::Kind::Identifier,
        Adamas::Compiler::Frontend::Token::Kind::Percent,
        Adamas::Compiler::Frontend::Token::Kind::Identifier,
        Adamas::Compiler::Frontend::Token::Kind::Plus,
        Adamas::Compiler::Frontend::Token::Kind::Identifier,
        Adamas::Compiler::Frontend::Token::Kind::EOF,
      ])
      tokens[1].span.start_offset.should eq(4)
      tokens[1].span.end_offset.should eq(5)
      tokens[1].span.start_line.should eq(1)
      control = percent_candidate_tokens("left+" + identifier + " + right")
      tokens[1].span.start_column.should eq(control[1].span.start_column)
      tokens[2].lexeme.should eq(identifier)
      tokens[2].span.start_offset.should eq(5)
      tokens[2].span.end_offset.should eq(5 + identifier.bytesize)
      tokens[2].span.start_line.should eq(1)
      tokens[2].span.start_column.should eq(control[2].span.start_column)
    end

    source = "left%qright"
    tokens = percent_candidate_tokens(source)
    tokens[1].kind.should eq(Adamas::Compiler::Frontend::Token::Kind::Percent)
    tokens[1].span.start_offset.should eq(4)
    tokens[1].span.end_offset.should eq(5)
    tokens[2].lexeme.should eq("qright")
    tokens[2].span.start_offset.should eq(5)
    tokens[2].span.end_offset.should eq(source.bytesize)
    tokens[2].span.start_line.should eq(1)
    control = percent_candidate_tokens("left+qright")
    tokens[1].span.start_column.should eq(control[1].span.start_column)
    tokens[2].span.start_column.should eq(control[2].span.start_column)

    multiline = percent_candidate_tokens("left%q\nright")
    multiline[3].kind.should eq(Adamas::Compiler::Frontend::Token::Kind::Newline)
    multiline[4].lexeme.should eq("right")
    multiline[4].span.start_offset.should eq(7)
    multiline[4].span.start_line.should eq(2)
    multiline[4].span.start_column.should eq(1)
  end

  it "leaves an incomplete percent type prefix untouched at end of input" do
    {"q", "Q", "r", "w", "i"}.each do |type_prefix|
      source = "left%" + type_prefix
      tokens = percent_candidate_tokens(source)

      tokens.map { |token| token.kind }.should eq([
        Adamas::Compiler::Frontend::Token::Kind::Identifier,
        Adamas::Compiler::Frontend::Token::Kind::Percent,
        Adamas::Compiler::Frontend::Token::Kind::Identifier,
        Adamas::Compiler::Frontend::Token::Kind::EOF,
      ])
      tokens[1].span.start_offset.should eq(4)
      tokens[1].span.end_offset.should eq(5)
      tokens[2].lexeme.should eq(type_prefix)
      tokens[2].span.start_offset.should eq(5)
      tokens[2].span.end_offset.should eq(source.bytesize)
      tokens[3].span.start_offset.should eq(source.bytesize)
    end

    source = "left%"
    tokens = percent_candidate_tokens(source)
    tokens.map { |token| token.kind }.should eq([
      Adamas::Compiler::Frontend::Token::Kind::Identifier,
      Adamas::Compiler::Frontend::Token::Kind::Percent,
      Adamas::Compiler::Frontend::Token::Kind::EOF,
    ])
    tokens[1].span.start_offset.should eq(4)
    tokens[1].span.end_offset.should eq(source.bytesize)
    tokens[2].span.start_offset.should eq(source.bytesize)
  end

  it "preserves byte offsets around failed lookahead after a multibyte prefix" do
    source = "\"é\" left%q\nright"
    tokens = percent_candidate_tokens(source)

    tokens.map { |token| token.kind }.should eq([
      Adamas::Compiler::Frontend::Token::Kind::String,
      Adamas::Compiler::Frontend::Token::Kind::Identifier,
      Adamas::Compiler::Frontend::Token::Kind::Percent,
      Adamas::Compiler::Frontend::Token::Kind::Identifier,
      Adamas::Compiler::Frontend::Token::Kind::Newline,
      Adamas::Compiler::Frontend::Token::Kind::Identifier,
      Adamas::Compiler::Frontend::Token::Kind::EOF,
    ])
    tokens[2].span.start_offset.should eq(9)
    tokens[2].span.end_offset.should eq(10)
    tokens[3].span.start_offset.should eq(10)
    tokens[3].span.end_offset.should eq(11)
    tokens[4].span.start_offset.should eq(11)
    tokens[5].span.start_offset.should eq(12)
    tokens[5].span.start_line.should eq(2)
    tokens[5].span.start_offset.should eq(source.bytesize - "right".bytesize)
  end

  it "parses modulo followed by percent-like identifiers as binary expressions" do
    {"i", "q", "Q", "r", "w", "x"}.each do |identifier|
      parser = Adamas::Compiler::Frontend::Parser.new(
        Adamas::Compiler::Frontend::Lexer.new("left%" + identifier)
      )
      program = parser.parse_program

      parser.diagnostics.should be_empty
      program.roots.size.should eq(1)
      binary = program.arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(binary).should eq(Adamas::Compiler::Frontend::NodeKind::Binary)
      Adamas::Compiler::Frontend.node_operator_string(binary).should eq("%")
      right = program.arena[Adamas::Compiler::Frontend.node_right(binary).not_nil!]
      Adamas::Compiler::Frontend.node_kind(right).should eq(Adamas::Compiler::Frontend::NodeKind::Identifier)
      Adamas::Compiler::Frontend.node_identifier_name_string(right).not_nil!.should eq(identifier)
    end
  end
end

