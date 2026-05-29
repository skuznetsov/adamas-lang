require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/type_inference_engine"

alias Frontend = Adamas::Compiler::Frontend
alias Semantic = Adamas::Compiler::Semantic

private def infer_atomic_cast_from_types(source : String)
  parser = Frontend::Parser.new(Frontend::Lexer.new(source))
  program = parser.parse_program

  analyzer = Semantic::Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names
  engine = analyzer.infer_types(name_result.identifier_symbols)

  {program, analyzer, engine}
end

describe Semantic::TypeInferenceEngine do
  describe "Atomic tuple overload inference" do
    it "does not route nil arguments into Tuple-annotated overloads" do
      source = <<-'CRYSTAL'
        struct Atomic(T)
          def probe
            cast_from(nil)
          end

          private def cast_from(value : Tuple)
            {% if T == Bool %}
              {value[0].unsafe_as(Bool), value[1]}
            {% else %}
              value
            {% end %}
          end

          private def cast_from(value)
            0
          end
        end

        value = uninitialized Atomic(Bool)
        value.probe
      CRYSTAL

      program, analyzer, engine = infer_atomic_cast_from_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Int32")
    end
  end
end
