require "spec"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/context"
require "../../src/compiler/semantic/macro_expander"
require "../../src/compiler/semantic/collectors/symbol_collector"

private def macro_nil_probe(source : String)
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  Adamas::Compiler::Semantic::MacroNodeValue.new(program.roots.first, program.arena, program.string_pool)
end

private def macro_nil_result(value : Adamas::Compiler::Semantic::MacroValue)
  value.call_method("nil?", [] of Adamas::Compiler::Semantic::MacroValue, nil)
    .as(Adamas::Compiler::Semantic::MacroBoolValue).value
end

describe "Macro nil? predicate" do
  it "recognizes absent values without emitting a literal" do
    value = Adamas::Compiler::Semantic::MacroNilValue.new
    macro_nil_result(value).should be_true
    value.stringify.should eq("")
  end

  it "recognizes an explicit nil AST while preserving its spelling" do
    value = macro_nil_probe("nil")
    macro_nil_result(value).should be_true
    value.stringify.should eq("nil")
  end

  it "distinguishes false and other non-nil AST nodes" do
    ["false", "0", "\"\"", "name", "[] of Int32"].each do |source|
      macro_nil_result(macro_nil_probe(source)).should be_false
    end
  end

  it "does not confuse false or empty values with absence" do
    values = [
      Adamas::Compiler::Semantic::MacroBoolValue.new(false),
      Adamas::Compiler::Semantic::MacroStringValue.new(""),
      Adamas::Compiler::Semantic::MacroNumberValue.new(0_i64),
    ] of Adamas::Compiler::Semantic::MacroValue
    values.each { |value| macro_nil_result(value).should be_false }
  end

  it "distinguishes missing, explicit nil and false declaration defaults" do
    {"value : Int32" => {true, ""}, "value : Int32? = nil" => {true, "nil"},
     "value : Bool = false" => {false, "false"}, "value : Int32 = 0" => {false, "0"}}.each do |source, expected|
      value = macro_nil_probe(source).call_method("value", [] of Adamas::Compiler::Semantic::MacroValue, nil)
      macro_nil_result(value).should eq(expected[0])
      value.stringify.should eq(expected[1])
    end
  end
end

private def macro_nil_condition_output(source : String)
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  context = Adamas::Compiler::Semantic::Context.new(Adamas::Compiler::Semantic::SymbolTable.new)
  Adamas::Compiler::Semantic::SymbolCollector.new(program, context).collect
  expander = Adamas::Compiler::Semantic::MacroExpander.new(program, program.arena, context.flags, symbol_table: context.symbol_table)
  output = expander.expand_top_level_text(program.roots.first, scope: context.symbol_table)
  expander.diagnostics.should be_empty
  output.strip
end

describe "Macro nil? conditions" do
  it "keeps literal nil available for the predicate in text conditions" do
    macro_nil_condition_output("{% if nil.nil? %}yes{% else %}no{% end %}").should eq("yes")
  end

  it "uses Boolean results for false and empty literal receivers" do
    macro_nil_condition_output("{% if false.nil? %}yes{% else %}no{% end %}").should eq("no")
    macro_nil_condition_output(%({% if \"\".nil? %}yes{% else %}no{% end %})).should eq("no")
  end
end
