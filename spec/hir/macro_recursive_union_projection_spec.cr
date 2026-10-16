require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_materialized_recursive_union(prewarm : Array(String), name : String = "Wire::Field")
    register_type_alias("Wire::Field", "Nil | Int32 | String | Array(Wire::Field) | Hash(String, Wire::Field)")
    register_type_alias("Wire::Integer", "Int32")
    prewarm.each { |type_name| type_ref_for_name(type_name) }
    macro_value_for_type_name(name).as(Adamas::Compiler::Semantic::MacroTypeValue)
  end
end

describe "Macro reflection after recursive union materialization" do
  [
    [] of String,
    ["Wire::Field"],
    ["Array(Wire::Field)"],
    ["Wire::Field", "Array(Wire::Field)", "Wire::Field"],
    ["Array(Nil | Int32 | String | Array(Wire::Field) | Hash(String, Wire::Field))"],
  ].each do |prewarm|
    it "retains recursive alias boundaries after #{prewarm.inspect}" do
      converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
      value = converter.__test_materialized_recursive_union(prewarm)
      members = value.union_members.not_nil!
      members.size.should eq(5)
      value.display_name.should eq("(Array(Wire::Field) | Hash(String, Wire::Field) | Int32 | String | Nil)")
      array = members.find { |member| member.as(Adamas::Compiler::Semantic::MacroTypeValue).name.starts_with?("Array(") }.not_nil!.as(Adamas::Compiler::Semantic::MacroTypeValue)
      arg = array.type_var_values.not_nil!.first.as(Adamas::Compiler::Semantic::MacroTypeValue)
      arg.name.should eq("Wire::Field")
      arg.call_method("union?", [] of Adamas::Compiler::Semantic::MacroValue, nil).to_macro_output.should eq("false")
    end
  end

  it "deduplicates equivalent generic arms without expanding recursive aliases" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    value = converter.__test_materialized_recursive_union([] of String,
      "Wire::Field | Array(String?) | Array(Nil | String) | Int32")
    members = value.union_members.not_nil!
    members.size.should eq(6)
    value.display_name.should eq("(Array(String | Nil) | Array(Wire::Field) | Hash(String, Wire::Field) | Int32 | String | Nil)")
  end

  it "deduplicates ordinary aliases inside generic arms" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    value = converter.__test_materialized_recursive_union([] of String,
      "Wire::Field | Array(Wire::Integer) | Array(Int32)")
    value.union_members.not_nil!.size.should eq(6)
    value.display_name.should eq("(Array(Int32) | Array(Wire::Field) | Hash(String, Wire::Field) | Int32 | String | Nil)")
  end

  it "keeps an explicitly expanded generic argument a union" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    value = converter.__test_materialized_recursive_union([] of String,
      "Array(Nil | Int32 | String | Array(Wire::Field) | Hash(String, Wire::Field))")
    arg = value.type_var_values.not_nil!.first.as(Adamas::Compiler::Semantic::MacroTypeValue)
    arg.call_method("union?", [] of Adamas::Compiler::Semantic::MacroValue, nil).to_macro_output.should eq("true")
    arg.union_members.not_nil!.size.should eq(5)
  end
end
