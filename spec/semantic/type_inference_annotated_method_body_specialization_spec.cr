require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/type_inference_engine"

alias Frontend = CrystalV2::Compiler::Frontend
alias Semantic = CrystalV2::Compiler::Semantic

private def infer_annotated_method_body_specialization_types(source : String)
  parser = Frontend::Parser.new(Frontend::Lexer.new(source))
  program = parser.parse_program

  analyzer = Semantic::Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names
  engine = analyzer.infer_types(name_result.identifier_symbols)

  {program, analyzer, engine}
end

describe Semantic::TypeInferenceEngine do
  describe "annotated wrapper bodies with narrower call-site args" do
    it "re-infers Nil-annotated wrappers when they specialize generic inner calls" do
      source = <<-CRYSTAL
        class Reference
        end

        class Foo < Reference
          def finalize
            nil
          end
        end

        module GC
          module Boehm
            alias Finalizer = Void*, Void* -> Nil

            def self.sink(obj : Void*, cb : Finalizer, data : Void*)
              nil
            end

            def self.add_finalizer(object : Reference) : Nil
              add_finalizer_impl(object)
            end

            def self.add_finalizer(object)
            end

            private def self.add_finalizer_impl(object : T) forall T
              sink(object.as(Void*), ->(obj, data) { obj.as(T).finalize }, nil)
            end
          end
        end

        def register(ref : Reference)
          GC::Boehm.add_finalizer(ref) if ref.responds_to?(:finalize)
        end

        register(Foo.new)
      CRYSTAL

      program, analyzer, engine = infer_annotated_method_body_specialization_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.select(&.level.error?).should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Nil")
    end
  end
end
