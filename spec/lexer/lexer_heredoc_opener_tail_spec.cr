require "spec"

require "../../src/compiler/frontend/lexer"

alias HeredocOpenerTailFrontend = Adamas::Compiler::Frontend

private def heredoc_opener_tail_tokens(source : String) : Array(HeredocOpenerTailFrontend::Token)
  tokens = [] of HeredocOpenerTailFrontend::Token
  HeredocOpenerTailFrontend::Lexer.new(source).each_token(skip_trivia: true) do |token|
    tokens << token
  end
  tokens
end

describe "heredoc opener-line tokens" do
  it "keeps postfix modifiers in token order and resumes after the heredoc terminator" do
    source = "{% raise <<-TXT if false\n  false guard must not raise\n  TXT\n%}\nafter_call\n"
    tokens = heredoc_opener_tail_tokens(source)

    literal_index = tokens.index! { |token| token.kind == HeredocOpenerTailFrontend::Token::Kind::String }
    modifier_index = tokens.index! { |token| token.kind == HeredocOpenerTailFrontend::Token::Kind::If }
    condition_index = tokens.index! { |token| token.kind == HeredocOpenerTailFrontend::Token::Kind::False }
    after_call = tokens.find do |token|
      token.kind == HeredocOpenerTailFrontend::Token::Kind::Identifier && token.lexeme == "after_call"
    end.not_nil!

    literal = tokens[literal_index]
    modifier = tokens[modifier_index]
    condition = tokens[condition_index]

    literal_index.should be < modifier_index
    modifier_index.should be < condition_index
    literal.span.start_offset.should eq(source.index("<<-TXT").not_nil!)
    modifier.span.start_offset.should eq(source.index("if false").not_nil!)
    condition.span.start_offset.should eq(source.index("false\n").not_nil!)
    modifier.span.start_offset.should be < literal.span.end_offset
    after_call.span.start_offset.should eq(source.index("after_call").not_nil!)
    after_call.span.start_offset.should be > literal.span.end_offset
  end

  it "keeps postfix unless and its condition in the opener-line token stream" do
    source = "{% raise <<-TXT unless true\n  guard is not taken\n  TXT\n%}"
    tokens = heredoc_opener_tail_tokens(source)
    modifier = tokens.find { |token| token.kind == HeredocOpenerTailFrontend::Token::Kind::Unless }.not_nil!
    condition = tokens.find { |token| token.kind == HeredocOpenerTailFrontend::Token::Kind::True }.not_nil!
    literal = tokens.find { |token| token.kind == HeredocOpenerTailFrontend::Token::Kind::String }.not_nil!

    modifier.span.start_offset.should eq(source.index("unless true").not_nil!)
    condition.span.start_offset.should eq(source.index("true\n").not_nil!)
    literal.span.start_offset.should be < modifier.span.start_offset
    modifier.span.start_offset.should be < literal.span.end_offset
  end

  it "keeps call sibling punctuation and arguments after a heredoc opener" do
    source = "sink(<<-TXT, 7)\n  payload\n  TXT\n"
    tokens = heredoc_opener_tail_tokens(source)
    selected = tokens.select do |token|
      token.kind.in?(
        HeredocOpenerTailFrontend::Token::Kind::LParen,
        HeredocOpenerTailFrontend::Token::Kind::String,
        HeredocOpenerTailFrontend::Token::Kind::Comma,
        HeredocOpenerTailFrontend::Token::Kind::Number,
        HeredocOpenerTailFrontend::Token::Kind::RParen,
      )
    end

    selected.map(&.kind).should eq([
      HeredocOpenerTailFrontend::Token::Kind::LParen,
      HeredocOpenerTailFrontend::Token::Kind::String,
      HeredocOpenerTailFrontend::Token::Kind::Comma,
      HeredocOpenerTailFrontend::Token::Kind::Number,
      HeredocOpenerTailFrontend::Token::Kind::RParen,
    ])
    selected[2].span.start_offset.should eq(source.index(", 7)").not_nil!)
    selected[3].span.start_offset.should eq(source.index("7)").not_nil!)
  end

  it "keeps multiple heredoc bodies in opener order" do
    source = "sink(<<-FIRST, <<-SECOND)\n  first body\n  FIRST\n  second body\n  SECOND\n"
    tokens = heredoc_opener_tail_tokens(source)
    literals = tokens.select { |token| token.kind == HeredocOpenerTailFrontend::Token::Kind::String }

    literals.size.should eq(2)
    String.new(literals[0].slice).should contain("first body")
    String.new(literals[1].slice).should contain("second body")
  end

  it "preserves CRLF opener suffix tokens and following source positions" do
    source = "sink(<<-TXT, 7)\r\n  payload\r\n  TXT\r\nmarker\r\n"
    tokens = heredoc_opener_tail_tokens(source)
    comma = tokens.find { |token| token.kind == HeredocOpenerTailFrontend::Token::Kind::Comma }.not_nil!
    number = tokens.find { |token| token.kind == HeredocOpenerTailFrontend::Token::Kind::Number }.not_nil!
    marker = tokens.find do |token|
      token.kind == HeredocOpenerTailFrontend::Token::Kind::Identifier && token.lexeme == "marker"
    end.not_nil!
    literal = tokens.find { |token| token.kind == HeredocOpenerTailFrontend::Token::Kind::String }.not_nil!

    comma.span.start_offset.should eq(source.index(", 7)").not_nil!)
    number.span.start_offset.should eq(source.index("7)").not_nil!)
    literal.span.end_line.should eq(4)
    literal.span.end_column.should eq(1)
    marker.span.start_offset.should eq(source.index("marker").not_nil!)
    marker.span.start_line.should eq(4)
    marker.span.start_column.should eq(1)
  end
end
