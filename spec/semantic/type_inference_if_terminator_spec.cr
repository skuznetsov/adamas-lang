require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/type_inference_engine"

alias Frontend = Adamas::Compiler::Frontend
alias Semantic = Adamas::Compiler::Semantic

private def infer_if_terminator_types(source : String)
  parser = Frontend::Parser.new(Frontend::Lexer.new(source))
  program = parser.parse_program

  analyzer = Semantic::Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names
  engine = analyzer.infer_types(name_result.identifier_symbols)

  {program, analyzer, engine}
end

describe Semantic::TypeInferenceEngine do
  describe "if expressions with terminating branches" do
    it "drops raise-only else branches from the result union" do
      source = <<-CRYSTAL
        class Ch
          def receive
            nil
          end
        end

        class Probe
          def initialize
            @channel = Ch.new
          end

          private def channel
            if channel = @channel
              channel
            else
              raise "BUG"
            end
          end

          def run
            channel.receive
          end
        end

        Probe.new.run
      CRYSTAL

      program, analyzer, engine = infer_if_terminator_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.select(&.level.error?).should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Nil")
    end
  end
end
