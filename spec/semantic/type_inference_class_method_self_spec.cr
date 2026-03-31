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
  end
end
