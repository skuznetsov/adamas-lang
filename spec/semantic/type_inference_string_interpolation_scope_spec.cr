require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/type_inference_engine"

alias Frontend = CrystalV2::Compiler::Frontend
alias Semantic = CrystalV2::Compiler::Semantic

private def infer_string_interpolation_scope_types(source : String)
  parser = Frontend::Parser.new(Frontend::Lexer.new(source))
  program = parser.parse_program

  analyzer = Semantic::Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names
  engine = analyzer.infer_types(name_result.identifier_symbols)

  {program, analyzer, name_result, engine}
end

describe Semantic::TypeInferenceEngine do
  describe "name resolution for interpolation expressions" do
    it "keeps rescue-bound locals visible inside string interpolation" do
      source = <<-'CRYSTAL'
        trace_bootstrap = true

        begin
          raise "boom"
        rescue ex
          if trace_bootstrap
            debug_line = "exception=#{ex.class} message=#{ex.message.inspect}"
            debug_line
          end
          raise ex
        end
      CRYSTAL

      _program, analyzer, name_result, engine = infer_string_interpolation_scope_types(source)

      analyzer.semantic_diagnostics.should be_empty
      name_result.diagnostics.should be_empty
      engine.diagnostics.should be_empty
    end
  end
end
