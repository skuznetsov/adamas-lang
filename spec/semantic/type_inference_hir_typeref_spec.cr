require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/type_inference_engine"

alias Frontend = CrystalV2::Compiler::Frontend
alias Semantic = CrystalV2::Compiler::Semantic

private def infer_hir_typeref_types(source : String)
  parser = Frontend::Parser.new(Frontend::Lexer.new(source))
  program = parser.parse_program

  analyzer = Semantic::Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names
  engine = analyzer.infer_types(name_result.identifier_symbols)

  {program, analyzer, engine}
end

describe Semantic::TypeInferenceEngine do
  describe "nested receiverless new in HIR-style type refs" do
    it "supports receiverless new with outer aliases in nested modules" do
      source = <<-CRYSTAL
        module Crystal::HIR
          alias TypeId = UInt32

          struct TypeRef
            getter id : TypeId

            def initialize(@id : TypeId)
            end

            VOID = new(0_u32)
            BOOL = new(1_u32)

            def self.zero
              VOID
            end
          end
        end

        Crystal::HIR::TypeRef.zero.id
      CRYSTAL

      program, analyzer, engine = infer_hir_typeref_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.select(&.level.error?).should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("TypeId")
    end
  end
end
