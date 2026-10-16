require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_named_tuple_map_index_inference(expr : Adamas::Compiler::Frontend::ExprId, bindings : Hash(String, String)) : String?
    @current_typeof_locals = bindings.transform_values { |name| type_ref_for_name(name) }
    inferred = infer_type_from_expr(expr, nil)
    inferred.try { |type| get_type_name_from_ref(type) }
  end
end

private def infer_named_tuple_map_expression(source : String) : String?
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(program.arena,
    sources_by_arena: {program.arena.object_id.to_u64 => source})
  converter.no_prelude = true
  converter.__test_named_tuple_map_index_inference(program.roots.first, {
    "permission" => "NamedTuple(config: Bool, label: String, count: Int32)",
    "vhost" => "String",
    "array" => "Array(Int32)",
    "hash" => "Hash(String, Bool)",
  })
end

describe "NamedTuple literal index inference in generic block results" do
  { {"config", "Bool"}, {"label", "String"}, {"count", "Int32"} }.each do |key, expected|
    it "retains the exact type of :#{key}" do
      infer_named_tuple_map_expression("permission[:#{key}]").should eq(expected)
    end
  end

  it "infers every field of the mapped result independently" do
    inferred = infer_named_tuple_map_expression("{vhost: vhost, configure: permission[:config], label: permission[:label], count: permission[:count]}")
    inferred.should eq("NamedTuple(vhost: String, configure: Bool, label: String, count: Int32)")
  end

  it "does not borrow a field type for a missing key" do
    infer_named_tuple_map_expression("permission[:absent]").should be_nil
  end

  it "keeps ordinary Array index inference" do
    infer_named_tuple_map_expression("array[0]").should eq("Int32")
  end

  it "keeps ordinary Hash index inference" do
    infer_named_tuple_map_expression(%(hash["key"])).should eq("Bool")
  end
end
