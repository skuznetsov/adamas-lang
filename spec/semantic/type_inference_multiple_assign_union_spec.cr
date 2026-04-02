require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/type_inference_engine"

alias Frontend = CrystalV2::Compiler::Frontend
alias Semantic = CrystalV2::Compiler::Semantic

class Semantic::TypeInferenceEngine
  def __spec_destructured_multiple_assign_element_type(value_type : Semantic::Type, idx : Int32)
    destructured_multiple_assign_element_type(value_type, idx)
  end
end

private def infer_multiple_assign_union_types(source : String)
  parser = Frontend::Parser.new(Frontend::Lexer.new(source))
  program = parser.parse_program

  analyzer = Semantic::Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names
  engine = analyzer.infer_types(name_result.identifier_symbols)

  {program, analyzer, engine}
end

private def build_test_flag_type
  scope = Semantic::SymbolTable.new(nil)
  Semantic::EnumType.new(
    Semantic::EnumSymbol.new(
      "FlagValue",
      Frontend::ExprId.new(0),
      scope: scope,
      members: {"Required" => 0_i64, "Optional" => 1_i64, "None" => 2_i64},
      base_type: "Int32"
    )
  ).as(Semantic::Type)
end

describe Semantic::TypeInferenceEngine do
  describe "multiple assignment destructuring" do
    it "destructures union-of-tuples element-wise instead of binding the whole union" do
      source = <<-CRYSTAL
        value = 1
      CRYSTAL

      program, analyzer, engine = infer_multiple_assign_union_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty

      flag_type = build_test_flag_type
      tuple_a = Semantic::TupleType.new([Semantic::PrimitiveType.new("String"), flag_type] of Semantic::Type)
      tuple_b = Semantic::TupleType.new([Semantic::PrimitiveType.new("String"), flag_type] of Semantic::Type)
      union = Semantic::UnionType.new([tuple_a, tuple_b])

      element_type = engine.__spec_destructured_multiple_assign_element_type(union, 1)
      element_type.should be_a(Semantic::EnumType)
      element_type.as(Semantic::EnumType).symbol.name.should eq("FlagValue")
    end

    it "keeps the fallback when a union member is not destructurable" do
      source = <<-CRYSTAL
        value = 1
      CRYSTAL

      program, analyzer, engine = infer_multiple_assign_union_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty

      flag_type = build_test_flag_type
      tuple_type = Semantic::TupleType.new([Semantic::PrimitiveType.new("String"), flag_type] of Semantic::Type)
      union = Semantic::UnionType.new([tuple_type, flag_type] of Semantic::Type)

      engine.__spec_destructured_multiple_assign_element_type(union, 1).should be_nil
    end
  end
end
