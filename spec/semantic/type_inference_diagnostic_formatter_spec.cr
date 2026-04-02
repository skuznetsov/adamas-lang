require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/type_inference_engine"

alias Frontend = CrystalV2::Compiler::Frontend
alias Semantic = CrystalV2::Compiler::Semantic

private def infer_diagnostic_formatter_types(source : String)
  parser = Frontend::Parser.new(Frontend::Lexer.new(source))
  program = parser.parse_program

  analyzer = Semantic::Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names
  engine = analyzer.infer_types(name_result.identifier_symbols)

  {program, analyzer, engine}
end

describe Semantic::TypeInferenceEngine do
  describe "diagnostic formatter arithmetic" do
    it "keeps clamp-based underline math in Int32 space" do
      source = <<-CRYSTAL
        module Probe
          struct Span
            getter start_column : Int32
            getter end_column : Int32

            def initialize(@start_column : Int32, @end_column : Int32)
            end
          end

          def self.underline_segment(line : String, span : Span)
            length = line.size
            start_index = (span.start_column - 1).clamp(0, length)
            end_index = (span.end_column - 1).clamp(start_index, length)
            caret_count = end_index - start_index
            available = length - start_index
            {caret_count, available}
          end
        end

        Probe.underline_segment("hello", Probe::Span.new(2, 4))
      CRYSTAL

      program, analyzer, engine = infer_diagnostic_formatter_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.select(&.level.error?).should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Tuple(Int32, Int32)")
    end
  end
end
