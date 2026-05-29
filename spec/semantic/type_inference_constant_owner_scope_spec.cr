require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/type_inference_engine"

alias Frontend = Adamas::Compiler::Frontend
alias Semantic = Adamas::Compiler::Semantic

class Adamas::Compiler::Semantic::TypeInferenceEngine
  def __debug_reinfer_constant_symbol(symbol : Semantic::ConstantSymbol)
    infer_constant_value_expression(symbol.value, owner_class: symbol.owner_class, owner_module: symbol.owner_module)
  end

  def __debug_reinfer_constant_node(node : Frontend::ConstantNode)
    infer_constant(node)
  end
end

private def infer_constant_owner_scope_types(source : String)
  parser = Frontend::Parser.new(Frontend::Lexer.new(source))
  program = parser.parse_program

  analyzer = Semantic::Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names

  engine = Semantic::TypeInferenceEngine.new(program, name_result.identifier_symbols, analyzer.global_context.symbol_table)

  {program, analyzer, engine}
end

describe Semantic::TypeInferenceEngine do
  describe "constant owner scope replay" do
    it "preserves the defining class when replaying receiverless constant values" do
      source = <<-CRYSTAL
        module HIR
          struct TypeRef
            getter id : UInt32

            def initialize(@id : UInt32)
            end

            VOID = new(0_u32)
          end
        end
      CRYSTAL

      program, analyzer, engine = infer_constant_owner_scope_types(source)

      hir = analyzer.global_context.symbol_table.lookup("HIR").as(Semantic::ModuleSymbol)
      type_ref = hir.scope.lookup("TypeRef").as(Semantic::ClassSymbol)
      void_symbol = type_ref.scope.lookup("VOID").as(Semantic::ConstantSymbol)
      void_node = program.arena[void_symbol.node_id].as(Frontend::ConstantNode)

      engine.__debug_reinfer_constant_symbol(void_symbol).to_s.should eq("TypeRef")
      engine.__debug_reinfer_constant_node(void_node).to_s.should eq("TypeRef")
      engine.diagnostics.select(&.level.error?).should be_empty
    end
  end
end
