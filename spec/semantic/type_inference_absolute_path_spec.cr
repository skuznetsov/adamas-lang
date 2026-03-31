require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/type_inference_engine"

alias Frontend = CrystalV2::Compiler::Frontend
alias Semantic = CrystalV2::Compiler::Semantic

private def infer_absolute_path_types(source : String)
  parser = Frontend::Parser.new(Frontend::Lexer.new(source))
  program = parser.parse_program

  analyzer = Semantic::Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names
  engine = analyzer.infer_types(name_result.identifier_symbols)

  {program, analyzer, engine}
end

describe Semantic::TypeInferenceEngine do
  describe "absolute paths" do
    it "keeps ::Signal rooted at the top level inside shadowing modules" do
      source = <<-CRYSTAL
        module Crystal::System::Signal
          def self.shadowed
            nil
          end
        end

        enum Signal : Int32
          INT = 2
        end

        module Crystal::System::Threading
          def self.resume_signal
            ::Signal.new(2)
          end
        end

        Crystal::System::Threading.resume_signal
      CRYSTAL

      program, analyzer, engine = infer_absolute_path_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Signal")
    end
  end
end
