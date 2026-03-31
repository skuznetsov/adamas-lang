require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/type_inference_engine"

alias Frontend = CrystalV2::Compiler::Frontend
alias Semantic = CrystalV2::Compiler::Semantic

private def infer_array_builtin_types(source : String)
  parser = Frontend::Parser.new(Frontend::Lexer.new(source))
  program = parser.parse_program

  analyzer = Semantic::Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names
  engine = analyzer.infer_types(name_result.identifier_symbols)

  {program, analyzer, engine}
end

describe Semantic::TypeInferenceEngine do
  describe "array builtins" do
    it "supports Array#index! for byte arrays" do
      source = <<-CRYSTAL
        module ArrayIndexBangProbe
          def self.probe
            key_value = [0x66_u8, 0x3d_u8, 0x6f_u8]
            key_value.index!(0x3d_u8)
          end
        end

        ArrayIndexBangProbe.probe
      CRYSTAL

      program, analyzer, engine = infer_array_builtin_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.select(&.level.error?).should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Int32")
    end

    it "supports byte-slice fast_index through the array model" do
      source = <<-CRYSTAL
        module SliceFastIndexProbe
          def self.probe
            bytes = uninitialized UInt8[4]
            bytes.to_unsafe.to_slice(4).fast_index(0x00_u8, 0).not_nil!
          end
        end

        SliceFastIndexProbe.probe
      CRYSTAL

      program, analyzer, engine = infer_array_builtin_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.select(&.level.error?).should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Int32")
    end
  end
end
