require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/type_inference_engine"

alias Frontend = CrystalV2::Compiler::Frontend
alias Semantic = CrystalV2::Compiler::Semantic

private def infer_while_assignment_narrowing_types(source : String)
  parser = Frontend::Parser.new(Frontend::Lexer.new(source))
  program = parser.parse_program

  analyzer = Semantic::Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names
  engine = analyzer.infer_types(name_result.identifier_symbols)

  {program, analyzer, engine}
end

describe Semantic::TypeInferenceEngine do
  describe "while assignment narrowing" do
    it "narrows loop assignment values inside the while body" do
      source = <<-CRYSTAL
        class Reader
          def initialize
            @done = false
          end

          def next_digit : Int32?
            return nil if @done
            @done = true
            7
          end
        end

        def parse(reader : Reader)
          value = 0
          while digit = reader.next_digit
            value = value * 10 + digit
          end
          value
        end

        parse(Reader.new)
      CRYSTAL

      program, analyzer, engine = infer_while_assignment_narrowing_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.select(&.level.error?).should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Int32")
    end
  end
end
