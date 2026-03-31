require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/compile_shadow_aggregate"
require "../../src/compiler/semantic/type_inference_engine"

alias Frontend = CrystalV2::Compiler::Frontend
alias Semantic = CrystalV2::Compiler::Semantic

private def infer_named_arg_types(units : Array(NamedTuple(path: String, source: String)))
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
  describe "named argument method lookup" do
    it "infers proc pointer target signatures from pointer type expressions" do
      units = [
        {
          path: "/stdlib/thread.cr",
          source: <<-CRYSTAL,
            class Thread
              def self.thread_proc(data : Void*) : Void*
                data
              end
            end

            ->Thread.thread_proc(Void*)
          CRYSTAL
        },
      ]

      program, analyzer, engine = infer_named_arg_types(units)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty

      proc_type = engine.context.get_type(program.roots.last).as(Semantic::ProcType)
      proc_type.param_types.map(&.to_s).should eq(["Pointer(Void)"])
      proc_type.return_type.to_s.should eq("Pointer(Void)")
    end

    it "matches module methods called with named arguments" do
      units = [
        {
          path: "/stdlib/lib_c.cr",
          source: <<-CRYSTAL,
            lib LibC
              alias Int = Int32
              alias PthreadT = Int32

              struct PthreadAttrT
                value : Int32
              end

              fun pthread_create(thread : PthreadT*, attr : PthreadAttrT*, start : Void* -> Void*, arg : Void*) : Int
            end
          CRYSTAL
        },
        {
          path: "/stdlib/gc.cr",
          source: <<-CRYSTAL,
            module GC
              def self.pthread_create(thread : LibC::PthreadT*, attr : LibC::PthreadAttrT*, start : Void* -> Void*, arg : Void*)
                LibC.pthread_create(thread, attr, start, arg)
              end
            end
          CRYSTAL
        },
        {
          path: "/stdlib/pthread.cr",
          source: <<-CRYSTAL,
            class Thread
              @system_handle : LibC::PthreadT

              def initialize
                @system_handle = 0
              end

              def self.thread_proc(data : Void*) : Void*
                Pointer(Void).null
              end
            end

            module Crystal::System::Thread
              private def init_handle
                GC.pthread_create(
                  thread: pointerof(@system_handle),
                  attr: Pointer(LibC::PthreadAttrT).null,
                  start: ->Thread.thread_proc(Void*),
                  arg: self.as(Void*),
                )
              end
            end

            class Thread
              include Crystal::System::Thread

              def boot
                init_handle
              end
            end

            Thread.new.boot
          CRYSTAL
        },
      ]

      program, analyzer, engine = infer_named_arg_types(units)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Int32")
    end
  end
end
