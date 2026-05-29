require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/type_inference_engine"

alias Frontend = Adamas::Compiler::Frontend
alias Semantic = Adamas::Compiler::Semantic

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

    it "keeps typed empty proc arrays collection-shaped" do
      source = <<-CRYSTAL
        class Exception
        end

        module Crystal::AtExitHandlers
          def self.add(handler)
            handlers = [] of Int32, ::Exception? ->
            handlers << handler
            handlers
          end
        end

        Crystal::AtExitHandlers.add(->(status : Int32, ex : ::Exception?) { nil })
      CRYSTAL

      program, analyzer, engine = infer_proc_type_annotation_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).should be_a(Semantic::ArrayType)
    end

    it "matches untyped proc literals against lib fun callback signatures" do
      source = <<-CRYSTAL
        lib LibPCRE2
          type MatchContext = Void*
          type JITStack = Void
          fun jit_stack_assign(mcontext : MatchContext*, callable_function : Void* -> JITStack*, callable_data : Void*) : Void
        end

        module Regex
          module PCRE2
            def self.jit_stack : LibPCRE2::JITStack*
              Pointer(Void).null.as(LibPCRE2::JITStack*)
            end

            def self.assign(match_context : LibPCRE2::MatchContext*) : Nil
              LibPCRE2.jit_stack_assign(match_context, ->(_data) { Regex::PCRE2.jit_stack }, nil)
              nil
            end
          end
        end

        Regex::PCRE2.assign(Pointer(Void*).null)
      CRYSTAL

      program, analyzer, engine = infer_proc_type_annotation_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Nil")
    end
  end
end
