require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

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

  def __test_named_tuple_identity_ref(name : String, signature : Bool, namespace : String? = nil) : Adamas::HIR::TypeRef
    previous_class = @current_class
    previous_namespace = @current_namespace_override
    previous_signature = @signature_scan_mode
    begin
      @current_class = namespace.try { |owner| "#{owner}::Probe" }
      @current_namespace_override = namespace
      @signature_scan_mode = signature
      type_ref_for_name(resolve_type_name_in_context(name))
    ensure
      @current_class = previous_class
      @current_namespace_override = previous_namespace
      @signature_scan_mode = previous_signature
    end
  end

  def __test_named_tuple_identity_variants(type : Adamas::HIR::TypeRef) : Array(Adamas::HIR::TypeRef)
    ensure_union_descriptor_for_type_ref(type)
    union_descriptor_from_sidecar(type).not_nil!.variants.map do |variant|
      mir_to_hir_type_ref(variant.type_ref)
    end
  end
end

private def named_tuple_type_context_converter
  Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
end

private def metric_named_tuple_type
  "NamedTuple(name: String, value: Int32 | Int64 | UInt16, labels: Hash(String, String) | NamedTuple(vhost: String))"
end

private def named_tuple_identity_converter
  source = <<-CRYSTAL
    class NamedTupleIdentityChild
    end
    module NamedTupleIdentityScope
      class NamedTupleIdentityChild
      end
      class Probe
      end
    end
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
  converter.no_prelude = true
  converter.seed_top_level_type_names(["NamedTupleIdentityChild", "NamedTupleIdentityScope"])
  program.roots.each do |id|
    case node = arena[id]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    end
  end
  converter
end

describe "NamedTuple keys across type resolution contexts" do
  [false, true].each do |signature|
    it "retains selected field identity after a #{signature ? "signature" : "body"} resolution round trip" do
      converter = named_tuple_identity_converter
      namespace = "NamedTupleIdentityScope"
      root_child = converter.__test_named_tuple_identity_ref("::NamedTupleIdentityChild", signature)
      local_child = converter.__test_named_tuple_identity_ref("NamedTupleIdentityChild", signature, namespace)
      root_child.should_not eq(local_child)
      root = converter.__test_named_tuple_identity_ref(
        "::NamedTuple(value: ::NamedTupleIdentityChild | ::Int32)", signature, namespace)
      local = converter.__test_named_tuple_identity_ref(
        "NamedTuple(value: NamedTupleIdentityChild | Int32)", signature, namespace)
      root.should_not eq(local)
      root_descriptor = converter.module.get_type_descriptor(root).not_nil!
      local_descriptor = converter.module.get_type_descriptor(local).not_nil!
      root_descriptor.type_params.size.should eq(1)
      local_descriptor.type_params.size.should eq(1)
      root_variants = converter.__test_named_tuple_identity_variants(root_descriptor.type_params[0])
      local_variants = converter.__test_named_tuple_identity_variants(local_descriptor.type_params[0])
      root_variants.size.should eq(2)
      root_variants.should contain(root_child)
      root_variants.should contain(Adamas::HIR::TypeRef::INT32)
      local_variants.size.should eq(2)
      local_variants.should contain(local_child)
      local_variants.should contain(Adamas::HIR::TypeRef::INT32)
      root_descriptor.name.should_not contain("::NamedTuple")
      root_descriptor.name.should_not contain("value: ::")
      plain = converter.__test_named_tuple_identity_ref("NamedTuple(value: Int32)", signature, namespace)
      anchored = converter.__test_named_tuple_identity_ref("::NamedTuple(value: ::Int32)", signature, namespace)
      plain.should eq(anchored)
      converter.module.get_type_descriptor(plain).not_nil!.name.should eq("NamedTuple(value: Int32)")
    end
  end

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
    ).should eq("NamedTuple(value: ::Int32 | ::Int64, label: ::String)")
  end

  it "resolves absolute field types during a signature scan" do
    named_tuple_type_context_converter.__test_named_tuple_context(
      "::NamedTuple(value: ::Int32 | ::Int64, label: ::String)", true
    ).should eq("NamedTuple(value: ::Int32 | ::Int64, label: ::String)")
  end

  it "resolves every complete root-qualified NamedTuple union member" do
    named_tuple_type_context_converter.__test_named_tuple_context(
      "::NamedTuple(value: ::Int32) | ::NamedTuple(value: ::Int64)"
    ).should eq("::NamedTuple(value: ::Int32) | ::NamedTuple(value: ::Int64)")
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
    ).should eq("Array(::Int32 | ::Int64)")
  end

  it "qualifies only alias field values inside nested generic containers" do
    named_tuple_type_context_converter.__test_named_tuple_qualified_alias(
      "Array(NamedTuple(name: String, value: MetricValue | Int64, labels: NamedTuple(vhost: Label)))"
    ).should eq(
      "Array(NamedTuple(name: String, value: Metrics::MetricValue | Int64, labels: NamedTuple(vhost: Metrics::Label)))"
    )
  end
end
