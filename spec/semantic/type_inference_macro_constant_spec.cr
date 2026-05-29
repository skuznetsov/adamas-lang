require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/compile_shadow_aggregate"
require "../../src/compiler/semantic/type_inference_engine"

alias Frontend = Adamas::Compiler::Frontend
alias Semantic = Adamas::Compiler::Semantic

private def infer_macro_constant_types(units : Array(NamedTuple(path: String, source: String)))
  aggregate = Semantic::CompileShadowAggregate.build(units)
  program = aggregate.program

  analyzer = Semantic::Analyzer.new(program)
  analyzer.collect_symbols(
    node_file_path_provider: ->(expr_id : Frontend::ExprId) { aggregate.path_for(expr_id) },
    source_for_path_provider: ->(path : String) { aggregate.source_for_path(path) }
  )
  name_result = analyzer.resolve_names
  engine = analyzer.infer_types(name_result.identifier_symbols)

  {program, analyzer, engine}
end

describe Semantic::TypeInferenceEngine do
  describe "macro-defined constant values" do
    it "expands macro condition constants before using them in method bodies" do
      units = [
        {
          path: "/stdlib/lib_c.cr",
          source: <<-CRYSTAL,
            lib LibC
              alias Int = Int32

              SIGRTMIN = 40

              struct Sigaction
                dummy : Int32
              end

              fun sigaction(sig : Int32, act : Sigaction*, old : Void*) : Int
            end
          CRYSTAL
        },
        {
          path: "/stdlib/crystal/system/unix/pthread.cr",
          source: <<-CRYSTAL,
            module Crystal::System::Thread
              private SIG_SUSPEND =
                {% if LibC.has_constant?(:SIGRTMIN) %}
                  LibC::SIGRTMIN + 6
                {% else %}
                  25
                {% end %}

              def self.install
                action = LibC::Sigaction.new
                LibC.sigaction(SIG_SUSPEND, pointerof(action), nil)
              end
            end

            Crystal::System::Thread.install
          CRYSTAL
        },
      ]

      program, analyzer, engine = infer_macro_constant_types(units)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Int32")
    end
  end
end
