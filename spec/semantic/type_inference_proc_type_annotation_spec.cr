require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/type_inference_engine"

alias Frontend = CrystalV2::Compiler::Frontend
alias Semantic = CrystalV2::Compiler::Semantic

private def infer_proc_type_annotation_types(source : String)
  parser = Frontend::Parser.new(Frontend::Lexer.new(source))
  program = parser.parse_program

  analyzer = Semantic::Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names
  engine = analyzer.infer_types(name_result.identifier_symbols)

  {program, analyzer, engine}
end

describe Semantic::TypeInferenceEngine do
  describe "proc type annotations with wrapped parameter lists" do
    it "resolves alias targets of the form (A, B, C) ->" do
      source = <<-CRYSTAL
        lib LibC
          struct SiginfoT
          end

          alias SigactionHandlerT = (Int, SiginfoT*, Void*) ->
        end

        handler = uninitialized LibC::SigactionHandlerT
        handler
      CRYSTAL

      program, analyzer, engine = infer_proc_type_annotation_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).should be_a(Semantic::ProcType)
    end

    it "resolves block annotations of the form (A, B, C) ->" do
      source = <<-CRYSTAL
        lib LibC
          struct SiginfoT
          end
        end

        def install(& : (Int, LibC::SiginfoT*, Void*) ->)
          nil
        end

        install do |signum, info, data|
          nil
        end
      CRYSTAL

      program, analyzer, engine = infer_proc_type_annotation_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Nil")
    end

    it "keeps typed nested block params through specialized Slice.new overloads" do
      source = <<-CRYSTAL
        struct Pointer(T)
        end

        class Array(T)
          def to_unsafe : Pointer(T)
            Pointer(T).new
          end

          def size : Int32
            0
          end
        end

        struct Slice(T)
          def self.new(ptr : Pointer(T), size : Int32) : self
          end
        end

        module Unicode
          def self.canonical_compose!(codepoints : Array(Int32), & : Char ->)
            canonical_compose!(Slice.new(codepoints.to_unsafe, codepoints.size)) { |x| yield x.unsafe_chr }
          end

          private def self.canonical_compose!(codepoints : Slice(Int32), & : Int32 ->)
          end
        end

        Unicode.canonical_compose!(Array(Int32).new) { |ch| ch }
      CRYSTAL

      program, analyzer, engine = infer_proc_type_annotation_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
    end

    it "resolves generic cast targets inside typed finalizer proc literals" do
      source = <<-CRYSTAL
        lib LibGC
          alias LocalFinalizer = Void*, Void* ->
          fun register_finalizer_ignore_self(obj : Void*, fn : LocalFinalizer, cd : Void*, ofn : LocalFinalizer*, ocd : Void**)
        end

        class Foo
          def finalize
            nil
          end
        end

        module GC
          module Boehm
            def self.add_finalizer(object : Reference) : Nil
              add_finalizer_impl(object)
            end

            def self.add_finalizer(object)
            end

            private def self.add_finalizer_impl(object : T) forall T
              LibGC.register_finalizer_ignore_self(object.as(Void*),
                ->(obj, data) { obj.as(T).finalize },
                nil, nil, nil)
              nil
            end
          end
        end

        GC::Boehm.add_finalizer(Foo.new)
      CRYSTAL

      program, analyzer, engine = infer_proc_type_annotation_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Nil")
    end
  end
end
