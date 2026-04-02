require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/type_inference_engine"

alias Frontend = CrystalV2::Compiler::Frontend
alias Semantic = CrystalV2::Compiler::Semantic

private def infer_fun_def_scope_types(source : String)
  parser = Frontend::Parser.new(Frontend::Lexer.new(source))
  program = parser.parse_program

  analyzer = Semantic::Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names
  engine = analyzer.infer_types(name_result.identifier_symbols)

  {program, analyzer, engine}
end

describe Semantic::TypeInferenceEngine do
  describe "top-level fun defs with bodies" do
    it "keeps typed parameters in scope during eager body inference" do
      source = <<-'CRYSTAL'
        struct Pointer(T)
          def value : T
            uninitialized T
          end
        end

        class Exception
        end

        lib LibUnwind
          struct Exception
            getter exception_object : Void*
          end
        end

        fun __crystal_get_exception(unwind_ex : LibUnwind::Exception*) : UInt64
          unwind_ex.value.exception_object.address
        end

        1
      CRYSTAL

      _program, analyzer, engine = infer_fun_def_scope_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
    end
  end
end
