require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/type_inference_engine"

alias Frontend = Adamas::Compiler::Frontend
alias Semantic = Adamas::Compiler::Semantic

private def infer_typeof_receiver_types(source : String)
  parser = Frontend::Parser.new(Frontend::Lexer.new(source))
  program = parser.parse_program

  analyzer = Semantic::Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names
  engine = analyzer.infer_types(name_result.identifier_symbols)

  {program, analyzer, engine}
end

describe Semantic::TypeInferenceEngine do
  describe "typeof receivers" do
    it "treats typeof(...) as a class receiver for .new" do
      source = <<-CRYSTAL
        x = 1_i64
        y = typeof(x).new(2)
        y
      CRYSTAL

      program, analyzer, engine = infer_typeof_receiver_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Int64")
    end
  end
end
