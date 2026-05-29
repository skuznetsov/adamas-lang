require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/type_inference_engine"

alias Frontend = Adamas::Compiler::Frontend
alias Semantic = Adamas::Compiler::Semantic

private def infer_time_span_builtin_types(source : String)
  parser = Frontend::Parser.new(Frontend::Lexer.new(source))
  program = parser.parse_program

  analyzer = Semantic::Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names
  engine = analyzer.infer_types(name_result.identifier_symbols)

  {program, analyzer, engine}
end

describe Semantic::TypeInferenceEngine do
  describe "Time::Span numeric builtins" do
    it "supports Number#seconds and top-level overloaded sleep resolution" do
      source = <<-CRYSTAL
        abstract struct Number
        end

        struct Time::Span
        end

        def sleep(seconds : Number) : Nil
          sleep(seconds.seconds)
        end

        def sleep(time : Time::Span) : Nil
          nil
        end

        seconds = uninitialized Number
        sleep(seconds)
      CRYSTAL

      program, analyzer, engine = infer_time_span_builtin_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Nil")
    end
  end
end
