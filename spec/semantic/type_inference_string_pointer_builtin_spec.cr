require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/symbol_table"
require "../../src/compiler/semantic/symbol"
require "../../src/compiler/semantic/collectors/symbol_collector"
require "../../src/compiler/semantic/resolvers/name_resolver"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/types/type"
require "../../src/compiler/semantic/type_inference_engine"

module TypeInferenceStringPointerBuiltinSpecAliases
  alias Frontend = Adamas::Compiler::Frontend
  alias Semantic = Adamas::Compiler::Semantic
end

include TypeInferenceStringPointerBuiltinSpecAliases

private def infer_types_for_string_pointer_builtin(source : String)
  lexer = Frontend::Lexer.new(source)
  parser = Frontend::Parser.new(lexer)
  program = parser.parse_program

  analyzer = Semantic::Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names

  engine = Semantic::TypeInferenceEngine.new(program, name_result.identifier_symbols, analyzer.global_context.symbol_table)
  engine.infer_types

  {analyzer, engine}
end

describe Adamas::Compiler::Semantic::TypeInferenceEngine do
  it "resolves Pointer#memcmp results through String compare-style bodies" do
    source = <<-CRYSTAL
      class String
        def semantic_compare(other : self)
          cmp = to_unsafe.memcmp(other.to_unsafe, bytesize)
          cmp.sign
        end
      end

      "abc".semantic_compare("abd")
    CRYSTAL

    analyzer, engine = infer_types_for_string_pointer_builtin(source)

    analyzer.semantic_diagnostics.should be_empty
    analyzer.name_resolver_diagnostics.should be_empty
    engine.diagnostics.should be_empty
  end

  it "resolves String#includes? for Char on explicit String receivers" do
    source = <<-CRYSTAL
      class String
        def semantic_probe(ch : Char)
          chars = self
          chars.includes?(ch)
        end
      end

      "abc".semantic_probe('b')
    CRYSTAL

    analyzer, engine = infer_types_for_string_pointer_builtin(source)

    analyzer.semantic_diagnostics.should be_empty
    analyzer.name_resolver_diagnostics.should be_empty
    engine.diagnostics.should be_empty
  end

  it "resolves String#matches? for Regex receivers" do
    source = <<-CRYSTAL
      class Regex
      end

      class String
      end

      "abc".matches?(Regex.new)
    CRYSTAL

    analyzer, engine = infer_types_for_string_pointer_builtin(source)

    analyzer.semantic_diagnostics.should be_empty
    analyzer.name_resolver_diagnostics.should be_empty
    engine.diagnostics.should be_empty
  end

  it "binds String#each_char block params as Char" do
    source = <<-CRYSTAL
      value = 0
      "ab".each_char do |char|
        value = char.ord
      end
      value
    CRYSTAL

    analyzer, engine = infer_types_for_string_pointer_builtin(source)

    analyzer.semantic_diagnostics.should be_empty
    analyzer.name_resolver_diagnostics.should be_empty
    engine.diagnostics.should be_empty
  end

  it "binds String#each_char_with_index block params as Char and Int32" do
    source = <<-CRYSTAL
      total = 0
      "ab".each_char_with_index do |char, index|
        total = total + char.ord + index
      end
      total
    CRYSTAL

    analyzer, engine = infer_types_for_string_pointer_builtin(source)

    analyzer.semantic_diagnostics.should be_empty
    analyzer.name_resolver_diagnostics.should be_empty
    engine.diagnostics.should be_empty
  end
end
