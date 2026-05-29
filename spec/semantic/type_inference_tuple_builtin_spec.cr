require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/type_inference_engine"

alias Frontend = Adamas::Compiler::Frontend
alias Semantic = Adamas::Compiler::Semantic

private def infer_tuple_builtin_types(source : String)
  parser = Frontend::Parser.new(Frontend::Lexer.new(source))
  program = parser.parse_program

  analyzer = Semantic::Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names
  engine = analyzer.infer_types(name_result.identifier_symbols)

  {program, analyzer, engine}
end

describe Semantic::TypeInferenceEngine do
  describe "tuple builtins" do
    it "supports Tuple#min in method bodies" do
      source = <<-CRYSTAL
        module TupleMinProbe
          def self.probe(precision : UInt32)
            {precision, 10_u32}.min.to_i32! &+ 5
          end
        end

        TupleMinProbe.probe(3_u32)
      CRYSTAL

      program, analyzer, engine = infer_tuple_builtin_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.select(&.level.error?).should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Int32")
    end

    it "resolves Tuple#includes? through Indexable and Enumerable mixins" do
      source = <<-CRYSTAL
        module Enumerable(T)
          def includes?(obj) : Bool
            true
          end
        end

        struct Tuple(T, U)
          include Enumerable(T | U)
        end

        module TupleIncludesProbe
          def self.probe(entry : String?) : Bool
            excluded = {".", ".."}
            excluded.includes?(entry)
          end
        end

        TupleIncludesProbe.probe(".")
      CRYSTAL

      program, analyzer, engine = infer_tuple_builtin_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.select(&.level.error?).should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Bool")
    end

    it "binds tuple each block params through Union(*T) signatures" do
      source = <<-CRYSTAL
        class FD
          def file_descriptor_close(&) : Nil
          end
        end

        abstract class EventLoop
          def self.remove(fd : FD) : Nil
          end
        end

        struct Tuple(T)
          def each(& : Union(*T) ->) : Nil
            yield self[0]
            yield self[1]
          end
        end

        module TupleEachProbe
          @@pipe : {FD, FD} = {FD.new, FD.new}

          def self.run : Nil
            @@pipe.each do |pipe_io|
              EventLoop.remove(pipe_io)
              pipe_io.file_descriptor_close { }
            end
          end
        end

        TupleEachProbe.run
      CRYSTAL

      program, analyzer, engine = infer_tuple_builtin_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.select(&.level.error?).should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Nil")
    end
  end
end
