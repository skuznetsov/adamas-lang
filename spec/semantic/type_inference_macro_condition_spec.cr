require "spec"

require "../../src/runtime"
require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/context"
require "../../src/compiler/semantic/symbol_table"
require "../../src/compiler/semantic/symbol"
require "../../src/compiler/semantic/collectors/symbol_collector"
require "../../src/compiler/semantic/resolvers/name_resolver"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/type_inference_engine"

alias Frontend = Adamas::Compiler::Frontend
alias Semantic = Adamas::Compiler::Semantic

private def infer_macro_condition_types(source : String, enabled_flags : Array(String))
  lexer = Frontend::Lexer.new(source)
  parser = Frontend::Parser.new(lexer)
  program = parser.parse_program

  flags = Adamas::Runtime.target_flags.dup
  enabled_flags.each { |flag| flags << flag }
  context = Semantic::Context.new(Semantic::SymbolTable.new, flags)

  analyzer = Semantic::Analyzer.new(program, context)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names

  engine = Semantic::TypeInferenceEngine.new(
    program,
    name_result.identifier_symbols,
    analyzer.global_context.symbol_table,
    flags: analyzer.global_context.flags
  )
  engine.infer_types

  {analyzer, engine}
end

describe Semantic::TypeInferenceEngine do
  describe "macro condition builtins" do
    it "prunes dead {% if flag? %} branches during semantic inference" do
      source = <<-CRYSTAL
        {% if flag?(:semantic_probe) %}
          1
        {% else %}
          1 + "x"
        {% end %}
      CRYSTAL

      analyzer, engine = infer_macro_condition_types(source, ["semantic_probe"])

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.select(&.level.error?).should be_empty
    end

    it "prunes dead {% unless flag? %} branches during semantic inference" do
      source = <<-CRYSTAL
        {% unless flag?(:semantic_probe) %}
          1 + "x"
        {% else %}
          1
        {% end %}
      CRYSTAL

      analyzer, engine = infer_macro_condition_types(source, ["semantic_probe"])

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.select(&.level.error?).should be_empty
    end
  end
end
