require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/type_inference_engine"

alias Frontend = CrystalV2::Compiler::Frontend
alias Semantic = CrystalV2::Compiler::Semantic

private def infer_constructor_ivar_param_types(source : String)
  parser = Frontend::Parser.new(Frontend::Lexer.new(source))
  program = parser.parse_program

  analyzer = Semantic::Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names
  engine = analyzer.infer_types(name_result.identifier_symbols)

  {program, analyzer, engine}
end

describe Semantic::TypeInferenceEngine do
  describe "constructor ivar params" do
    it "registers typed block ivar params as instance variable types" do
      source = <<-CRYSTAL
        class Worker
          def initialize(&@proc : ->)
          end

          def run
            @proc.call
          end
        end

        Worker.new { nil }.run
      CRYSTAL

      program, analyzer, engine = infer_constructor_ivar_param_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
    end

    it "registers typed ivar params for nilable flow use" do
      source = <<-CRYSTAL
        class Worker
          def initialize(@name : String?)
          end

          def display
            if name = @name
              name
            else
              "anon"
            end
          end
        end

        Worker.new("sergey").display
      CRYSTAL

      program, analyzer, engine = infer_constructor_ivar_param_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("String")
    end
  end
end
