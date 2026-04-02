require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/type_inference_engine"
include CrystalV2::Compiler::Frontend
include CrystalV2::Compiler::Semantic

private def infer_types(source : String)
  lexer = Lexer.new(source)
  parser = Parser.new(lexer)
  program = parser.parse_program

  analyzer = Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names

  engine = TypeInferenceEngine.new(program, name_result.identifier_symbols, analyzer.global_context.symbol_table)
  engine.infer_types

  {program, analyzer, engine}
end

describe TypeInferenceEngine do
  describe "class methods annotated with self" do
    it "treats nested struct class-method self as an instance type" do
      source = <<-CRYSTAL
        @[Deprecated]
        module Float::Printer::IEEE
          extend self

          def normalized_boundaries(v : Float64) : {minus: Float::Printer::DiyFP, plus: Float::Printer::DiyFP}
            w = Float::Printer::DiyFP.from_f(v)
            {minus: Float::Printer::DiyFP.new((w.frac << 1) + 1, w.exp - 1), plus: w}
          end
        end

        @[Deprecated]
        struct Float::Printer::DiyFP
          property frac : UInt64
          property exp : Int32

          def initialize(@frac, @exp)
          end

          def self.from_f(v : Float64) : self
            new(1_u64, 2)
          end
        end
      CRYSTAL

      _program, _analyzer, engine = infer_types(source)

      engine.diagnostics.should be_empty
    end

    it "treats abstract class-method self as a virtual instance receiver" do
      source = <<-CRYSTAL
        abstract class Crystal::EventLoop
          def self.current : self
            LoopImpl.new
          end
        end

        class LoopImpl < Crystal::EventLoop
          def after_fork_before_exec : Nil
          end
        end

        Crystal::EventLoop.current.after_fork_before_exec
      CRYSTAL

      _program, _analyzer, engine = infer_types(source)

      engine.diagnostics.should be_empty
    end

    it "treats receiverless new inside class-method helpers as a constructor call" do
      source = <<-CRYSTAL
        class Gadget
          private def initialize(@path : String, @fd : Int32, @mode = "", @flag = nil, @encoding = nil, @invalid = nil)
          end

          def touch : Int32
            @fd
          end

          def self.new(path : String, mode = "r", perm = 0, encoding = nil, invalid = nil, flag = nil)
            build_internal(path, mode, perm, encoding, invalid, flag)
          end

          protected def self.build_internal(path, mode = "r", perm = 0, encoding = nil, invalid = nil, flag = nil, &)
            value = new(path, 1, mode, flag, encoding, invalid)
            begin
              yield value
            ensure
              value.touch
            end
          end

          def self.wrap(path : String, &)
            build_internal(path) do |value|
              yield value
            end
          end
        end

        Gadget.wrap("x") do |value|
          value.touch
        end
      CRYSTAL

      _program, _analyzer, engine = infer_types(source)

      engine.diagnostics.should be_empty
    end
  end

  describe "instance methods annotated with self" do
    it "resolves self parameters when called from a class method body" do
      source = <<-CRYSTAL
        class File
          struct Info
            def initialize
            end

            def same_file?(other : self) : Bool
              true
            end
          end

          def self.current
            pwd_info = Info.new
            dot_info = Info.new
            pwd_info.same_file?(dot_info)
          end
        end

        File.current
      CRYSTAL

      _program, _analyzer, engine = infer_types(source)

      engine.diagnostics.should be_empty
    end
  end
end
