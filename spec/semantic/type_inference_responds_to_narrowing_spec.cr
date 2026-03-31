require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/type_inference_engine"

alias Frontend = CrystalV2::Compiler::Frontend
alias Semantic = CrystalV2::Compiler::Semantic

private def infer_responds_to_narrowing_types(source : String)
  parser = Frontend::Parser.new(Frontend::Lexer.new(source))
  program = parser.parse_program

  analyzer = Semantic::Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names
  engine = analyzer.infer_types(name_result.identifier_symbols)

  {program, analyzer, engine}
end

describe Semantic::TypeInferenceEngine do
  describe "responds_to? flow narrowing" do
    it "narrows self to implementors inside guarded module methods" do
      source = <<-CRYSTAL
        abstract class IO
        end

        module IO::Buffered
          def pos : Int64
            if self.responds_to?(:unbuffered_pos)
              self.unbuffered_pos
            else
              0_i64
            end
          end
        end

        class IO::FileDescriptor < IO
          include IO::Buffered

          protected def unbuffered_pos : Int64
            0_i64
          end
        end

        IO::FileDescriptor.new.pos
      CRYSTAL

      program, analyzer, engine = infer_responds_to_narrowing_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Int64")
    end

    it "narrows identifiers to subclasses that implement the guarded method" do
      source = <<-CRYSTAL
        abstract class Device
        end

        class PositionalDevice < Device
          def unbuffered_pos : Int64
            7_i64
          end
        end

        def probe(device : Device)
          if device.responds_to?(:unbuffered_pos)
            device.unbuffered_pos
          else
            0_i64
          end
        end

        probe(PositionalDevice.new)
      CRYSTAL

      program, analyzer, engine = infer_responds_to_narrowing_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Int64")
    end
  end
end
