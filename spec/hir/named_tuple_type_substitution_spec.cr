require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_named_tuple_type_substitution(name : String, bindings : Hash(String, String), owner : String? = nil) : String
    @type_param_map = bindings
    @current_class = owner
    @subst_cache_gen += 1
    substitute_type_params_in_type_name(name)
  end
end

private def substitute_named_tuple_type(name : String, bindings = {} of String => String, owner : String? = nil)
  converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
  converter.__test_named_tuple_type_substitution(name, bindings, owner)
end

describe "NamedTuple field syntax during type parameter substitution" do
  it "keeps union-valued fields and nested label unions inside their keys" do
    substitute_named_tuple_type(
      "NamedTuple(value: UInt16 | Int32 | Float64, labels: Hash(String, String) | NamedTuple(vhost: String))"
    ).should eq(
      "NamedTuple(value: Float64 | Int32 | UInt16, labels: Hash(String, String) | NamedTuple(vhost: String))"
    )
  end

  it "substitutes field values while preserving keys that match parameters and self" do
    substitute_named_tuple_type(
      "NamedTuple(T: T, self: self, value: U)", {"T" => "Int32", "U" => "Int64"}, "MetricOwner"
    ).should eq("NamedTuple(T: Int32, self: MetricOwner, value: Int64)")
  end

  it "substitutes nested named tuples inside an ordinary generic container" do
    substitute_named_tuple_type(
      "Array(NamedTuple(value: T | Nil, nested: NamedTuple(T: T)))", {"T" => "Int32"}
    ).should eq("Array(NamedTuple(value: Nil | Int32, nested: NamedTuple(T: Int32)))")
  end

  it "preserves every complete NamedTuple union arm" do
    substitute_named_tuple_type(
      "NamedTuple(value: T) | NamedTuple(value: T, label: String)", {"T" => "Int32"}
    ).should eq("NamedTuple(value: Int32) | NamedTuple(value: Int32, label: String)")
  end

  it "keeps ordinary generic argument unions structurally unchanged" do
    substitute_named_tuple_type("Hash(String, T | Nil)", {"T" => "Int32"}).should eq("Hash(String, Nil | Int32)")
  end

  it "does not reinterpret an explicit root qualifier as a field separator" do
    substitute_named_tuple_type(
      "NamedTuple(value: ::Int32 | ::Int64, label: ::String)"
    ).should eq("NamedTuple(value: ::Int32 | ::Int64, label: ::String)")
  end
end
