require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/type_inference_engine"

alias Frontend = CrystalV2::Compiler::Frontend
alias Semantic = CrystalV2::Compiler::Semantic

private def infer_block_destructuring_types(source : String)
  parser = Frontend::Parser.new(Frontend::Lexer.new(source))
  program = parser.parse_program

  analyzer = Semantic::Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names
  engine = analyzer.infer_types(name_result.identifier_symbols)

  {program, analyzer, engine}
end

describe Semantic::TypeInferenceEngine do
  describe "tuple block destructuring" do
    it "destructures a yielded tuple across multiple block parameters" do
      source = <<-CRYSTAL
        module PairSource
          extend self

          def each(& : {String, String} ->)
            yield({"HOME", "/tmp"})
          end

          def keys : Array(String)
            keys = [] of String
            each { |key, _| keys << key }
            keys
          end
        end

        PairSource.keys
      CRYSTAL

      program, analyzer, engine = infer_block_destructuring_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.select(&.level.error?).should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Array(String)")
    end
  end
end
