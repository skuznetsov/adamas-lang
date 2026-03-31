require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/type_inference_engine"

alias Frontend = CrystalV2::Compiler::Frontend
alias Semantic = CrystalV2::Compiler::Semantic

private def infer_current_class_shadow_types(source : String)
  parser = Frontend::Parser.new(Frontend::Lexer.new(source))
  program = parser.parse_program

  analyzer = Semantic::Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names
  engine = analyzer.infer_types(name_result.identifier_symbols)

  {program, analyzer, engine}
end

describe Semantic::TypeInferenceEngine do
  describe "current class self-reference under included module shadowing" do
    it "keeps bare class identifiers bound to the current class inside instance methods" do
      source = <<-CRYSTAL
        module Crystal::System::Thread
        end

        class Thread
          include Crystal::System::Thread

          class LinkedList(T)
            def push(value : T) : Nil
            end

            def delete(value : T) : Nil
            end
          end

          @@threads = uninitialized Thread::LinkedList(Thread)

          protected def self.threads : Thread::LinkedList(Thread)
            @@threads
          end

          def initialize
            Thread.threads.push(self)
          end

          def finish
            Thread.threads.delete(self)
          end
        end

        Thread.new.finish
      CRYSTAL

      program, analyzer, engine = infer_current_class_shadow_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Nil")
    end

    it "keeps current namespace module receivers when they collide with the current class name" do
      source = <<-CRYSTAL
        module Crystal::System::Thread
          def self.thread_proc(data : Void*) : Void*
            data
          end

          def init_handle
            ->Thread.thread_proc(Void*)
          end
        end

        class Thread
          include Crystal::System::Thread
        end

        Thread.new.init_handle
      CRYSTAL

      program, analyzer, engine = infer_current_class_shadow_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Proc(Pointer(Void), Pointer(Void))")
    end
  end
end
