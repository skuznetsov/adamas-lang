require "spec"

require "../../src/compiler/frontend/parser"
require "../../src/compiler/lsp/server"

module SemanticTokensSpecHelper
  # Legend as defined in LSP::Server::SemanticTokenType
  def self.legend_index(name : String)
    case name
    when "namespace"     then 0
    when "type"          then 1
    when "class"         then 2
    when "enum"          then 3
    when "interface"     then 4
    when "struct"        then 5
    when "typeParameter" then 6
    when "parameter"     then 7
    when "variable"      then 8
    when "property"      then 9
    when "enumMember"    then 10
    when "event"         then 11
    when "function"      then 12
    when "method"        then 13
    when "macro"         then 14
    when "keyword"       then 15
    when "modifier"      then 16
    when "comment"       then 17
    when "string"        then 18
    when "number"        then 19
    when "regexp"        then 20
    when "operator"      then 21
    else                      -1
    end
  end

  def self.collect(program, source)
    server = CrystalV2::Compiler::LSP::Server.new
    server.collect_semantic_tokens(program, source)
  end

  def self.collect_source(source : String)
    parser = CrystalV2::Compiler::Frontend::Parser.new(
      CrystalV2::Compiler::Frontend::Lexer.new(source)
    )
    program = parser.parse_program
    collect(program, source)
  end

  def self.collect_source_with_fast_lexical(source : String, enabled : Bool)
    old_value = ENV["LSP_FAST_LEXICAL_TOKENS"]?
    if enabled
      ENV.delete("LSP_FAST_LEXICAL_TOKENS")
    else
      ENV["LSP_FAST_LEXICAL_TOKENS"] = "0"
    end

    collect_source(source)
  ensure
    if old_value
      ENV["LSP_FAST_LEXICAL_TOKENS"] = old_value
    else
      ENV.delete("LSP_FAST_LEXICAL_TOKENS")
    end
  end

  def self.collect_range(program, source, range)
    server = CrystalV2::Compiler::LSP::Server.new
    server.collect_semantic_tokens(program, source, nil, nil, nil, nil, range)
  end

  def self.decode(tokens : CrystalV2::Compiler::LSP::SemanticTokens, source : String)
    data = tokens.data
    line = 0
    start = 0
    out = [] of Tuple(Int32, Int32, Int32, Int32, String)
    i = 0
    lines = source.lines
    while i < data.size
      dl = data[i]; ds = data[i + 1]; length = data[i + 2]; kind = data[i + 3]; mods = data[i + 4]
      line += dl
      start = (dl == 0) ? start + ds : ds
      text = lines[line]? || ""
      snippet = length > 0 ? text.byte_slice(start, length) : ""
      out << {line + 1, start + 1, length, kind, snippet}
      i += 5
    end
    out
  end

  it "highlights members and nested identifiers" do
    source = "a = foo.bar(b[0]) { x }\n"
    parser = CrystalV2::Compiler::Frontend::Parser.new(
      CrystalV2::Compiler::Frontend::Lexer.new(source)
    )
    program = parser.parse_program
    tokens = SemanticTokensSpecHelper.collect(program, source)
    decoded = SemanticTokensSpecHelper.decode(tokens, source)

    # Expect variable 'a'
    decoded.any? { |(_, _, _, kind, text)| kind == SemanticTokensSpecHelper.legend_index("variable") && text == "a" }.should be_true
    # Expect receiver 'foo'
    decoded.any? { |(_, _, _, kind, text)| kind == SemanticTokensSpecHelper.legend_index("variable") && text == "foo" }.should be_true
    # Expect index target 'b' and number '0'
    decoded.any? { |(_, _, _, kind, text)| kind == SemanticTokensSpecHelper.legend_index("variable") && text == "b" }.should be_true
    decoded.any? { |(_, _, _, kind, text)| kind == SemanticTokensSpecHelper.legend_index("number") && text == "0" }.should be_true
    # Expect method member 'bar'
    decoded.any? { |(_, _, _, kind, text)| kind == SemanticTokensSpecHelper.legend_index("method") && text == "bar" }.should be_true
    # Expect block var 'x'
    decoded.any? { |(_, _, _, kind, text)| kind == SemanticTokensSpecHelper.legend_index("variable") && text == "x" }.should be_true
  end

  it "highlights control flow keywords" do
    source = "if cond\n  begin\n    do_something\n  end\nend\n"
    parser = CrystalV2::Compiler::Frontend::Parser.new(
      CrystalV2::Compiler::Frontend::Lexer.new(source)
    )
    program = parser.parse_program
    tokens = SemanticTokensSpecHelper.collect(program, source)
    decoded = SemanticTokensSpecHelper.decode(tokens, source)

    decoded.any? { |(_, _, _, kind, text)| kind == SemanticTokensSpecHelper.legend_index("keyword") && text == "if" }.should be_true
    decoded.any? { |(_, _, _, kind, text)| kind == SemanticTokensSpecHelper.legend_index("keyword") && text == "begin" }.should be_true
    decoded.count { |(_, _, _, kind, text)| kind == SemanticTokensSpecHelper.legend_index("keyword") && text == "end" }.should be >= 2
  end

  it "highlights symbol literals in hash access" do
    source = "options[:accel_usage_log] = true\n"
    parser = CrystalV2::Compiler::Frontend::Parser.new(
      CrystalV2::Compiler::Frontend::Lexer.new(source)
    )
    program = parser.parse_program
    tokens = SemanticTokensSpecHelper.collect(program, source)
    decoded = SemanticTokensSpecHelper.decode(tokens, source)

    enum_member_kind = SemanticTokensSpecHelper.legend_index("enumMember")
    decoded.any? { |(_, _, _, kind, text)| kind == enum_member_kind && text == ":accel_usage_log" }.should be_true
  end

  it "keeps full lexical fast path identical to the lexer oracle for covered fixtures" do
    fixtures = [
      "if cond\n  begin\n    VALUE = :speed\n  end\nend\n",
      "# if Fake\nVALUE = :speed\ntext = \"done\"\n",
      "value:Int32 = Foo::Bar.new\n",
      %("#{:foo}"),
      "rx = /foo/\n",
      "match = body_text.match(/=\\s*(\\w+(?:::\\w+)*)::/)\n",
      "ratio = a / b\n",
    ]

    fixtures.each do |source|
      fast = SemanticTokensSpecHelper.collect_source_with_fast_lexical(source, true)
      lexer = SemanticTokensSpecHelper.collect_source_with_fast_lexical(source, false)

      fast.data.should eq(lexer.data)
    end
  end

  it "lexically marks symbol literals inside string interpolation" do
    source = %("#{:foo}")
    lexer = CrystalV2::Compiler::Frontend::Lexer.new(source)
    parser = CrystalV2::Compiler::Frontend::Parser.new(lexer)
    program = parser.parse_program
    tokens = SemanticTokensSpecHelper.collect(program, source)
    decoded = SemanticTokensSpecHelper.decode(tokens, source)

    string_kind = SemanticTokensSpecHelper.legend_index("string")
    decoded.any? { |(_, _, _, kind, text)| kind == string_kind && text.includes?("foo") }.should be_true
  end

  it "skips trivia while preserving lexical symbols and strings" do
    source = "# if Fake\nVALUE = :speed\ntext = \"done\"\n"
    parser = CrystalV2::Compiler::Frontend::Parser.new(
      CrystalV2::Compiler::Frontend::Lexer.new(source)
    )
    program = parser.parse_program
    tokens = SemanticTokensSpecHelper.collect(program, source)
    decoded = SemanticTokensSpecHelper.decode(tokens, source)
    texts = decoded.map { |(_, _, _, _, text)| text }

    texts.should_not contain("Fake")
    decoded.any? { |(_, _, _, kind, text)| kind == SemanticTokensSpecHelper.legend_index("keyword") && text == "if" }.should be_false
    decoded.any? { |(_, _, _, kind, text)| kind == SemanticTokensSpecHelper.legend_index("type") && text == "VALUE" }.should be_true
    decoded.any? { |(_, _, _, kind, text)| kind == SemanticTokensSpecHelper.legend_index("enumMember") && text == ":speed" }.should be_true
    decoded.any? { |(_, _, _, kind, text)| kind == SemanticTokensSpecHelper.legend_index("string") && text == "\"done\"" }.should be_true
  end

  it "limits semantic token range responses to the requested visible window" do
    source = "alpha = 1\nbeta = foo.bar(:speed)\ngamma = \"done\"\n"
    parser = CrystalV2::Compiler::Frontend::Parser.new(
      CrystalV2::Compiler::Frontend::Lexer.new(source)
    )
    program = parser.parse_program
    range = CrystalV2::Compiler::LSP::Range.new(
      CrystalV2::Compiler::LSP::Position.new(1, 0),
      CrystalV2::Compiler::LSP::Position.new(1, source.lines[1].bytesize)
    )

    tokens = SemanticTokensSpecHelper.collect_range(program, source, range)
    decoded = SemanticTokensSpecHelper.decode(tokens, source)
    texts = decoded.map { |(_, _, _, _, text)| text }

    texts.should contain("beta")
    texts.should contain("foo")
    texts.should contain("bar")
    texts.should contain(":speed")
    texts.should_not contain("alpha")
    texts.should_not contain("gamma")
  end

  it "advertises semantic token range support" do
    capabilities = CrystalV2::Compiler::LSP::ServerCapabilities.new
    provider = capabilities.semantic_tokens_provider.not_nil!

    provider["range"].as_bool.should be_true
    provider["full"]["delta"].as_bool.should be_true
  end
end
