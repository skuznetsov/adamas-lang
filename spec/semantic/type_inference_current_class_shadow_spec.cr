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

  describe "included module lexical parent lookup" do
    it "does not pull parent module methods into instance method lookup" do
      source = <<-CRYSTAL
        module System
          def self.print(handle : Int32, bytes : String) : Nil
          end

          module FileDescriptor
          end
        end

        abstract class IO
          def print(obj : _) : Nil
          end

          def print(*objects : _) : Nil
          end
        end

        class IO::FileDescriptor < IO
          include System::FileDescriptor

          def initialize
          end
        end

        STDERR = IO::FileDescriptor.new

        module Crystal
          def self.exit
            STDERR.print "Unhandled exception: "
          end
        end

        Crystal.exit
      CRYSTAL

      program, analyzer, engine = infer_current_class_shadow_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Nil")
    end

    it "prefers inherited instance methods over colliding class-method references" do
      source = <<-CRYSTAL
        class Base
          struct Info
            def initialize
            end

            def size : Int32
              42
            end
          end

          def info : Base::Info
            Base::Info.new
          end
        end

        class File < Base
          def self.info(path : String) : Base::Info
            Base::Info.new
          end

          def size : Int32
            info.size
          end
        end

        File.new.size
      CRYSTAL

      program, analyzer, engine = infer_current_class_shadow_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Int32")
    end

    it "resolves inherited nested return annotations for bare receiver chains" do
      source = <<-CRYSTAL
        class Container
          struct Info
            def initialize
            end

            def size : Int32
              42
            end
          end
        end

        class Base
          def info : Container::Info
            Container::Info.new
          end
        end

        class Container < Base
          def self.info(path : String) : Container::Info
            Container::Info.new
          end

          def size : Int32
            info.size
          end
        end

        Container.new.size
      CRYSTAL

      program, analyzer, engine = infer_current_class_shadow_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Int32")
    end

    it "keeps bare info receiver chains working in the live File naming corridor" do
      source = <<-CRYSTAL
        module Crystal::System::File
          def self.shadowed
            nil
          end
        end

        class IO
          class FileDescriptor
            def info : File::Info
              File::Info.new
            end
          end
        end

        class File < IO::FileDescriptor
          struct Info
            def initialize
            end

            def size : Int32
              42
            end
          end

          def self.info(path : String) : File::Info
            File::Info.new
          end

          def size : Int32
            info.size
          end
        end

        File.new.size
      CRYSTAL

      program, analyzer, engine = infer_current_class_shadow_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Int32")
    end
  end
end
