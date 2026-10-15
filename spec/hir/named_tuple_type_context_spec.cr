require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_named_tuple_context(name : String, signature : Bool = false) : String
    previous = @signature_scan_mode
    @signature_scan_mode = signature
    begin
      resolve_type_name_in_context(name)
    ensure
      @signature_scan_mode = previous
    end
  end

  def __test_named_tuple_declared_context(name : String) : String
    normalize_declared_type_name(name)
  end

  def __test_named_tuple_qualified_alias(name : String) : String
    qualify_alias_target_in_context(name, "Metrics")
  end

  def __test_named_tuple_owner_context(name : String, signature : Bool = false) : String
    register_type_alias("Metrics::MetricValue", "Int32 | Int64")
    register_type_alias("Metrics::Label", "String")
    @current_class = "Metrics::Reader(Int32)"
    @type_param_map = {"T" => "Int32"}
    @subst_cache_gen += 1
    @signature_scan_mode = signature
    resolve_type_name_in_context(name)
  end
end

private def named_tuple_type_context_converter
  Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
end

private def metric_named_tuple_type
  "NamedTuple(name: String, value: Int32 | Int64 | UInt16, labels: Hash(String, String) | NamedTuple(vhost: String))"
end

describe "NamedTuple keys across type resolution contexts" do
  it "preserves keys while resolving field unions in a body" do
    named_tuple_type_context_converter.__test_named_tuple_context(metric_named_tuple_type).should eq(metric_named_tuple_type)
  end

  it "preserves keys during a signature scan" do
    named_tuple_type_context_converter.__test_named_tuple_context(metric_named_tuple_type, true).should eq(metric_named_tuple_type)
  end

  it "preserves keys when normalizing a declared type" do
    named_tuple_type_context_converter.__test_named_tuple_declared_context(metric_named_tuple_type).should eq(metric_named_tuple_type)
  end

  it "resolves absolute field types without stripping syntax from keys" do
    named_tuple_type_context_converter.__test_named_tuple_context(
      "::NamedTuple(value: ::Int32 | ::Int64, label: ::String)"
    ).should eq("NamedTuple(value: Int32 | Int64, label: String)")
  end

  it "resolves absolute field types during a signature scan" do
    named_tuple_type_context_converter.__test_named_tuple_context(
      "::NamedTuple(value: ::Int32 | ::Int64, label: ::String)", true
    ).should eq("NamedTuple(value: Int32 | Int64, label: String)")
  end

  it "resolves every complete root-qualified NamedTuple union member" do
    named_tuple_type_context_converter.__test_named_tuple_context(
      "::NamedTuple(value: ::Int32) | ::NamedTuple(value: ::Int64)"
    ).should eq("NamedTuple(value: Int32) | NamedTuple(value: Int64)")
  end

  it "qualifies lexical field aliases in generic-owner body and signature contexts" do
    [false, true].each do |signature|
      named_tuple_type_context_converter.__test_named_tuple_owner_context(
        "Array(NamedTuple(value: MetricValue, label: Label))", signature
      ).should eq("Array(NamedTuple(value: Metrics::MetricValue, label: Metrics::Label))")
    end
  end

  it "keeps field keys named after self and type parameters intact" do
    named_tuple_type_context_converter.__test_named_tuple_owner_context(
      "NamedTuple(T: T, self: self)"
    ).should eq("NamedTuple(T: Int32, self: Metrics::Reader(Int32))")
  end

  it "resolves ordinary generic union arguments with explicit root qualification" do
    named_tuple_type_context_converter.__test_named_tuple_context(
      "Array(::Int32 | ::Int64)"
    ).should eq("Array(Int32 | Int64)")
  end

  it "qualifies only alias field values inside nested generic containers" do
    named_tuple_type_context_converter.__test_named_tuple_qualified_alias(
      "Array(NamedTuple(name: String, value: MetricValue | Int64, labels: NamedTuple(vhost: Label)))"
    ).should eq(
      "Array(NamedTuple(name: String, value: Metrics::MetricValue | Int64, labels: NamedTuple(vhost: Metrics::Label)))"
    )
  end
end
