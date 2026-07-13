require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/type_inference_engine"

alias Frontend = Adamas::Compiler::Frontend
alias Semantic = Adamas::Compiler::Semantic

private def infer_generic_union_annotation_types(source : String)
  parser = Frontend::Parser.new(Frontend::Lexer.new(source))
  program = parser.parse_program

  analyzer = Semantic::Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names
  engine = analyzer.infer_types(name_result.identifier_symbols)

  {program, analyzer, engine}
end

describe Semantic::TypeInferenceEngine do
  describe "generic annotations with union members" do
    it "keeps top-level union parsing inside generic module receivers" do
      source = <<-CRYSTAL
        module Enumerable(T)
          abstract def each(& : T ->)
        end

        class Box
          include Enumerable(Int32 | String)

          def each(& : (Int32 | String) ->)
            yield 1
          end
        end

        def probe(values : Enumerable(Int32 | String))
          values.each do |value|
            value
          end
        end

        probe(Box.new)
      CRYSTAL

      program, analyzer, engine = infer_generic_union_annotation_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty

      box = analyzer.global_context.symbol_table.lookup("Box").should be_a(Semantic::ClassSymbol)
      enumerable = box.as(Semantic::ClassSymbol).scope.included_modules.find { |ref| ref.name == "Enumerable" }
      enumerable.should_not be_nil
      enumerable.not_nil!.type_arg_names.should eq(["Int32 | String"])
      engine.context.get_type(program.roots.last).to_s.should eq("Int32")
    end

    it "limits virtual module dispatch to includers with matching type arguments" do
      source = <<-CRYSTAL
        module Enumerable(T)
          abstract def each(& : T ->)
        end

        class IntBox
          include Enumerable(Int32)

          def each(& : Int32 ->)
            yield 1
          end
        end

        class StringBox
          include Enumerable(String)

          def each(& : String ->)
            yield "wrong"
          end
        end

        def probe(values : Enumerable(Int32))
          values.each do |value|
            value
          end
        end

        probe(IntBox.new)
      CRYSTAL

      program, analyzer, engine = infer_generic_union_annotation_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Int32")
    end
  end
end
