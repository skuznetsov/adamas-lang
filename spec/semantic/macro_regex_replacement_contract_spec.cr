require "spec"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/macro_expander"

include Adamas::Compiler

private def __test_regex_replacement_expand(expression : String) : String
  parser = Frontend::Parser.new(Frontend::Lexer.new("{% begin %}\n{{ #{expression} }}\n{% end %}"))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  expander = Semantic::MacroExpander.new(program, program.arena, Set(String).new)
  output = expander.expand_top_level_text(program.roots.first)
  expander.diagnostics.should be_empty
  output.strip
end

describe "macro regex replacement contract" do
  it "replaces every namespace separator in StringLiteral and MacroId receivers" do
    __test_regex_replacement_expand(%("Outer::Inner".gsub(/:/, "_"))).should eq(%("Outer__Inner"))
    __test_regex_replacement_expand(%("Outer::Inner".id.gsub(/:/, "_").stringify)).should eq(%("Outer__Inner"))
  end

  it "keeps the receiver node kind after replacement" do
    __test_regex_replacement_expand(%("A:B".gsub(/:/, "_").class_name)).should eq(%("StringLiteral"))
    __test_regex_replacement_expand(%("A:B".id.gsub(/:/, "_").class_name)).should eq(%("MacroId"))
  end

  it "preserves case insensitive, multiline and extended regex flags" do
    __test_regex_replacement_expand(%("V2".gsub(/^v/i, ""))).should eq(%("2"))
    __test_regex_replacement_expand(%("a\\nb".gsub(/a.b/m, "x"))).should eq(%("x"))
    __test_regex_replacement_expand(%("abc".gsub(/a b/x, "z"))).should eq(%("zc"))
  end

  it "supports captures and zero width matches without changing unmatched text" do
    __test_regex_replacement_expand(%("v2.8".gsub(/^v(.*)$/, "\\\\1"))).should eq(%("2.8"))
    __test_regex_replacement_expand(%("ab".gsub(/(?=b)/, "x"))).should eq(%("axb"))
    __test_regex_replacement_expand(%("abc".gsub(/z/, "x"))).should eq(%("abc"))
  end

  it "rejects incorrect arity and named arguments" do
    expect_raises(ArgumentError) { __test_regex_replacement_expand(%("abc".gsub(/a/))) }
    expect_raises(ArgumentError) { __test_regex_replacement_expand(%("abc".gsub(regex: /a/, replacement: "x"))) }
  end

  it "rejects non regex patterns and non string replacements" do
    expect_raises(ArgumentError) { __test_regex_replacement_expand(%("abc".gsub("a", "x"))) }
    expect_raises(ArgumentError) { __test_regex_replacement_expand(%("abc".gsub(/a/, 1))) }
    expect_raises(ArgumentError) { __test_regex_replacement_expand(%("abc".gsub(/a/, 'x'))) }
  end

  it "rejects invalid regular expressions" do
    expect_raises(ArgumentError) { __test_regex_replacement_expand(%|"abc".gsub(/(/, "x")|) }
  end
end
