require "spec"
require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_canonical_union_type_ref(name : String) : Adamas::HIR::TypeRef
    type_ref_for_name(name)
  end

  def __test_canonical_union_type_name(name : String) : String
    get_type_name_from_ref(type_ref_for_name(name))
  end

  def __test_canonical_union_type_name(name : String, type_params : Hash(String, String)) : String
    with_isolated_type_param_map(type_params) do
      get_type_name_from_ref(type_ref_for_name(name))
    end
  end

  def __test_canonical_union_type_ref(name : String, type_params : Hash(String, String)) : Adamas::HIR::TypeRef
    with_isolated_type_param_map(type_params) do
      type_ref_for_name(name)
    end
  end

  def __test_seed_nominal_canonical_union_cache(name : String) : Adamas::HIR::TypeRef
    stale = @module.intern_type(
      Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Generic,
        name,
        [Adamas::HIR::TypeRef::CHAR, Adamas::HIR::TypeRef::CHAR],
      ),
    )
    @type_cache[type_cache_key(name)] = stale
    stale
  end

  def __test_canonical_union_cache_entry(name : String) : Adamas::HIR::TypeRef?
    @type_cache[type_cache_key(name)]?
  end
end

describe "Canonical Union constructor references" do
  it "collapses duplicate arms to the concrete type" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)

    converter.__test_canonical_union_type_name("Union(Char, Char)").should eq("Char")
  end

  it "replaces a stale nominal Generic cache entry with the canonical type" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    name = "Union(Char, Char)"
    stale = converter.__test_seed_nominal_canonical_union_cache(name)

    converter.module.get_type_descriptor(stale).not_nil!.kind.should eq(Adamas::HIR::TypeKind::Generic)
    converter.__test_canonical_union_type_ref(name).should eq(Adamas::HIR::TypeRef::CHAR)
    converter.__test_canonical_union_cache_entry(name).should eq(Adamas::HIR::TypeRef::CHAR)
  end

  it "preserves distinct arms and flattens nested unions" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)

    converter.__test_canonical_union_type_name("Union(Char, String)").should eq("Char | String")
    converter.__test_canonical_union_type_name("Union(String | Nil, String)").should eq("Nil | String")
  end

  it "normalizes a generic Union nested in StaticArray" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    static_array = converter.__test_canonical_union_type_ref("StaticArray(Union(Char, Char), 2)")
    descriptor = converter.module.get_type_descriptor(static_array)

    descriptor.should_not be_nil
    descriptor.not_nil!.kind.should eq(Adamas::HIR::TypeKind::Array)
    descriptor.not_nil!.type_params.first?.should eq(Adamas::HIR::TypeRef::CHAR)
  end

  it "normalizes the tuple-splat Union form after type substitution" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    mapping = {
      "T"        => "Char",
      "T__tuple" => "Char, Char",
    }

    converter.__test_canonical_union_type_name("Union(*T)", mapping).should eq("Char")
  end

  it "does not materialize a union when an arm is still an unresolved type parameter" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    mapping = {"U" => "Bool"}

    converter.__test_canonical_union_type_ref("Union(T, Char)", mapping).should eq(Adamas::HIR::TypeRef::VOID)
  end
end
