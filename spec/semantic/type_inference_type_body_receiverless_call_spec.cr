require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/type_inference_engine"

alias Frontend = Adamas::Compiler::Frontend
alias Semantic = Adamas::Compiler::Semantic

private def infer_type_body_receiverless_types(source : String)
  parser = Frontend::Parser.new(Frontend::Lexer.new(source))
  program = parser.parse_program

  analyzer = Semantic::Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names
  engine = analyzer.infer_types(name_result.identifier_symbols)

  {program, analyzer, engine}
end

describe Semantic::TypeInferenceEngine do
  describe "receiverless calls in type bodies" do
    it "treats bare calls in class bodies as implicit self calls on the type" do
      source = <<-CRYSTAL
        struct Int128
          MIN = new(1)

          def self.new(value)
            value
          end
        end

        Int128::MIN
      CRYSTAL

      program, analyzer, engine = infer_type_body_receiverless_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Int32")
    end

    it "infers struct constants through owner-scoped path resolution" do
      source = <<-CRYSTAL
        struct Int128
          MIN = new(1) << 127
          MAX = ~MIN

          def self.new(value : String, base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : self
            value.to_i128 base: base, whitespace: whitespace, underscore: underscore, prefix: prefix, strict: strict, leading_zero_is_octal: leading_zero_is_octal
          end

          def self.new(value) : self
            value.to_i128
          end

          def self.new!(value) : self
            value.to_i128!
          end
        end

        Int128::MIN
      CRYSTAL

      program, analyzer, engine = infer_type_body_receiverless_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Int128")
    end
  end
end
