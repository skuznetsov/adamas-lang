require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/compile_shadow_aggregate"
require "../../src/compiler/semantic/type_inference_engine"

alias Frontend = CrystalV2::Compiler::Frontend
alias Semantic = CrystalV2::Compiler::Semantic

private def infer_pthread_mutex_types(units : Array(NamedTuple(path: String, source: String)))
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
  describe "pthread mutex semantic lookup across lib reopens" do
    it "resolves pthread mutex lib funs from reopened LibC scopes" do
      units = [
        {
          path: "/stdlib/lib_c.cr",
          source: <<-CRYSTAL,
            lib LibC
              alias Int = Int32
            end
          CRYSTAL
        },
        {
          path: "/stdlib/lib_c/aarch64-darwin/c/sys/types.cr",
          source: <<-CRYSTAL,
            lib LibC
              struct PthreadMutexT
                value : Int32
              end
            end
          CRYSTAL
        },
        {
          path: "/stdlib/lib_c/aarch64-darwin/c/pthread.cr",
          source: <<-CRYSTAL,
            lib LibC
              fun pthread_mutex_lock(x0 : PthreadMutexT*) : Int
              fun pthread_mutex_unlock(x0 : PthreadMutexT*) : Int
              fun pthread_mutex_destroy(x0 : PthreadMutexT*) : Int
            end
          CRYSTAL
        },
        {
          path: "/stdlib/errno.cr",
          source: <<-CRYSTAL,
            class Errno
              def self.new(value : Int32)
                value
              end
            end
          CRYSTAL
        },
        {
          path: "/stdlib/crystal/system/unix/pthread_mutex.cr",
          source: <<-CRYSTAL,
            class Thread
              class Mutex
                def lock
                  ret = LibC.pthread_mutex_lock(self)
                  Errno.new(ret)
                end

                def unlock
                  ret = LibC.pthread_mutex_unlock(self)
                  Errno.new(ret)
                end

                def finalize
                  ret = LibC.pthread_mutex_destroy(self)
                  Errno.new(ret)
                end

                def to_unsafe
                  pointerof(@mutex)
                end
              end
            end
          CRYSTAL
        },
      ]

      _program, analyzer, engine = infer_pthread_mutex_types(units)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
    end

    it "keeps pthread mutex bodies valid across placeholder and outer class reopens" do
      units = [
        {
          path: "/stdlib/lib_c.cr",
          source: <<-CRYSTAL,
            lib LibC
              alias Int = Int32
            end
          CRYSTAL
        },
        {
          path: "/stdlib/lib_c/aarch64-darwin/c/sys/types.cr",
          source: <<-CRYSTAL,
            lib LibC
              struct PthreadMutexT
                value : Int32
              end
            end
          CRYSTAL
        },
        {
          path: "/stdlib/lib_c/aarch64-darwin/c/pthread.cr",
          source: <<-CRYSTAL,
            lib LibC
              fun pthread_mutex_lock(x0 : PthreadMutexT*) : Int
              fun pthread_mutex_unlock(x0 : PthreadMutexT*) : Int
              fun pthread_mutex_destroy(x0 : PthreadMutexT*) : Int
            end
          CRYSTAL
        },
        {
          path: "/stdlib/errno.cr",
          source: <<-CRYSTAL,
            class Errno
              def self.new(value : Int32)
                value
              end
            end
          CRYSTAL
        },
        {
          path: "/stdlib/crystal/system/thread_mutex.cr",
          source: <<-CRYSTAL,
            class Thread
              class Mutex
              end
            end
          CRYSTAL
        },
        {
          path: "/stdlib/crystal/system/thread.cr",
          source: <<-CRYSTAL,
            class Thread
              def self.current
                uninitialized Thread
              end
            end
          CRYSTAL
        },
        {
          path: "/stdlib/crystal/system/unix/pthread_mutex.cr",
          source: <<-CRYSTAL,
            class Thread
              class Mutex
                def lock
                  ret = LibC.pthread_mutex_lock(self)
                  Errno.new(ret)
                end

                def unlock
                  ret = LibC.pthread_mutex_unlock(self)
                  Errno.new(ret)
                end

                def finalize
                  ret = LibC.pthread_mutex_destroy(self)
                  Errno.new(ret)
                end

                def to_unsafe
                  pointerof(@mutex)
                end
              end
            end
          CRYSTAL
        },
      ]

      _program, analyzer, engine = infer_pthread_mutex_types(units)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
    end
  end
end
