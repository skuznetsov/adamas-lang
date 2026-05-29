require "spec"

require "../../src/main"
require "../../src/compiler/frontend/lexer"

describe Adamas::Compiler::Frontend::Lexer do
  it "tokenizes identifiers and numbers" do
    source = "foo 123\nbar"
    lexer = Adamas::Compiler::Frontend::Lexer.new(source)
    kinds = [] of Adamas::Compiler::Frontend::Token::Kind
    lexer.each_token { |token| kinds << token.kind }

    kinds.should eq([
      Adamas::Compiler::Frontend::Token::Kind::Identifier,
      Adamas::Compiler::Frontend::Token::Kind::Whitespace,
      Adamas::Compiler::Frontend::Token::Kind::Number,
      Adamas::Compiler::Frontend::Token::Kind::Newline,
      Adamas::Compiler::Frontend::Token::Kind::Identifier,
      Adamas::Compiler::Frontend::Token::Kind::EOF,
    ])
  end

  it "keeps plain double braces inside regular strings" do
    source = "value = text.includes?(\"{{\")\nafter_call"
    lexer = Adamas::Compiler::Frontend::Lexer.new(source)
    tokens = [] of Adamas::Compiler::Frontend::Token
    lexer.each_token(skip_trivia: true) { |token| tokens << token }

    string_tokens = tokens.select { |token| token.kind == Adamas::Compiler::Frontend::Token::Kind::String }
    string_tokens.size.should eq(1)
    String.new(string_tokens.first.slice).should eq("{{")
    tokens.none? { |token| token.kind == Adamas::Compiler::Frontend::Token::Kind::StringInterpolation }.should be_true
    tokens.any? { |token| token.kind == Adamas::Compiler::Frontend::Token::Kind::Identifier && String.new(token.slice) == "after_call" }.should be_true
  end

  it "keeps macro control markers inside plain comments" do
    source = "# {%\n"
    lexer = Adamas::Compiler::Frontend::Lexer.new(source)
    tokens = [] of Adamas::Compiler::Frontend::Token
    lexer.each_token(skip_trivia: false) { |token| tokens << token }

    comments = tokens.select { |token| token.kind == Adamas::Compiler::Frontend::Token::Kind::Comment }
    comments.size.should eq(1)
    String.new(comments.first.slice).should eq("# {%")
    tokens.any? { |token| token.kind == Adamas::Compiler::Frontend::Token::Kind::LBracePercent }.should be_false
  end

  it "breaks comment lexing before macro control after interpolation close" do
    source = "# }{% end %}\n"
    lexer = Adamas::Compiler::Frontend::Lexer.new(source)
    tokens = [] of Adamas::Compiler::Frontend::Token
    lexer.each_token(skip_trivia: false) { |token| tokens << token }

    comments = tokens.select { |token| token.kind == Adamas::Compiler::Frontend::Token::Kind::Comment }
    comments.size.should eq(1)
    String.new(comments.first.slice).should eq("# }")
    tokens.any? { |token| token.kind == Adamas::Compiler::Frontend::Token::Kind::LBracePercent && String.new(token.slice) == "{%" }.should be_true
    tokens.any? { |token| token.kind == Adamas::Compiler::Frontend::Token::Kind::PercentRBrace && String.new(token.slice) == "%}" }.should be_true
  end

  it "tokenizes escaped strings to processed payloads" do
    source = "\"\\n\""
    lexer = Adamas::Compiler::Frontend::Lexer.new(source)
    tokens = [] of Adamas::Compiler::Frontend::Token
    lexer.each_token(skip_trivia: true) { |token| tokens << token }

    tokens[0].kind.should eq(Adamas::Compiler::Frontend::Token::Kind::String)
    String.new(tokens[0].slice).should eq("\n")
    tokens.last.kind.should eq(Adamas::Compiler::Frontend::Token::Kind::EOF)
  end

  it "tokenizes symbol literals and path separators without zero-length tokens" do
    source = ":foo A::B"
    lexer = Adamas::Compiler::Frontend::Lexer.new(source)
    tokens = [] of Adamas::Compiler::Frontend::Token
    lexer.each_token(skip_trivia: true) { |token| tokens << token }

    tokens.map(&.kind).should eq([
      Adamas::Compiler::Frontend::Token::Kind::Symbol,
      Adamas::Compiler::Frontend::Token::Kind::Identifier,
      Adamas::Compiler::Frontend::Token::Kind::ColonColon,
      Adamas::Compiler::Frontend::Token::Kind::Identifier,
      Adamas::Compiler::Frontend::Token::Kind::EOF,
    ])
    String.new(tokens[0].slice).should eq(":foo")
    String.new(tokens[2].slice).should eq("::")
  end

  it "keeps type declaration colons as standalone tokens" do
    source = "a : Int32"
    lexer = Adamas::Compiler::Frontend::Lexer.new(source)
    tokens = [] of Adamas::Compiler::Frontend::Token
    lexer.each_token(skip_trivia: false) { |token| tokens << token }

    colon = tokens.find { |token| token.kind == Adamas::Compiler::Frontend::Token::Kind::Colon }
    colon.should_not be_nil
    String.new(colon.not_nil!.slice).should eq(":")
    tokens.none? { |token| token.kind == Adamas::Compiler::Frontend::Token::Kind::Colon && token.slice.empty? }.should be_true
  end

  it "tracks sequential macro block boundaries without corrupting the block stack" do
    source = <<-CRYSTAL
    macro first
    end

    macro second
    end
    CRYSTAL

    lexer = Adamas::Compiler::Frontend::Lexer.new(source)
    kinds = [] of Adamas::Compiler::Frontend::Token::Kind
    lexer.each_token(skip_trivia: true) { |token| kinds << token.kind }

    kinds.should eq([
      Adamas::Compiler::Frontend::Token::Kind::Macro,
      Adamas::Compiler::Frontend::Token::Kind::Identifier,
      Adamas::Compiler::Frontend::Token::Kind::Newline,
      Adamas::Compiler::Frontend::Token::Kind::End,
      Adamas::Compiler::Frontend::Token::Kind::Newline,
      Adamas::Compiler::Frontend::Token::Kind::Newline,
      Adamas::Compiler::Frontend::Token::Kind::Macro,
      Adamas::Compiler::Frontend::Token::Kind::Identifier,
      Adamas::Compiler::Frontend::Token::Kind::Newline,
      Adamas::Compiler::Frontend::Token::Kind::End,
      Adamas::Compiler::Frontend::Token::Kind::EOF,
    ])
  end
end
