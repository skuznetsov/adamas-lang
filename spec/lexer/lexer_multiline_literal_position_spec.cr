require "../spec_helper"

private def multiline_position_tokens(source : String)
  tokens = [] of Adamas::Compiler::Frontend::Token
  Adamas::Compiler::Frontend::Lexer.new(source).each_token(skip_trivia: true) do |token|
    tokens << token
  end
  tokens
end

private def multiline_position_marker(source : String)
  multiline_position_tokens(source).find do |token|
    token.kind == Adamas::Compiler::Frontend::Token::Kind::Identifier && String.new(token.slice) == "marker"
  end.not_nil!
end

describe "multiline literal source positions" do
  it "counts heredoc content lines once and restores columns after a delimiter prefix" do
    source = "value = <<-TEXT\n  TEXT suffix\n  payload\n  TEXT\n    marker\n"
    tokens = multiline_position_tokens(source)
    literal = tokens.find(&.kind.==(Adamas::Compiler::Frontend::Token::Kind::String)).not_nil!
    literal.span.end_line.should eq(5)
    literal.span.end_column.should eq(1)
    marker = multiline_position_marker(source)
    marker.span.start_line.should eq(5)
    marker.span.start_column.should eq(5)
    marker.span.start_offset.should eq(source.index("marker"))
  end

  it "keeps heredoc positions correct with CRLF source lines" do
    source = "value = <<-TEXT\n  payload\n  TEXT\n    marker\n".gsub("\n", "\r\n")
    marker = multiline_position_marker(source)
    marker.span.start_line.should eq(4)
    marker.span.start_column.should eq(5)
    marker.span.start_offset.should eq(source.index("marker"))
  end

  it "counts newlines in percent strings once" do
    marker = multiline_position_marker("value = %q{first\nsecond}\n    marker\n")
    marker.span.start_line.should eq(3)
    marker.span.start_column.should eq(5)
  end

  it "counts newlines in percent regexes once" do
    marker = multiline_position_marker("value = %r{first\nsecond}\n    marker\n")
    marker.span.start_line.should eq(3)
    marker.span.start_column.should eq(5)
  end

  it "keeps ordinary multiline strings on their source line" do
    marker = multiline_position_marker("value = \"first\nsecond\"\n    marker\n")
    marker.span.start_line.should eq(3)
    marker.span.start_column.should eq(5)
  end
end
