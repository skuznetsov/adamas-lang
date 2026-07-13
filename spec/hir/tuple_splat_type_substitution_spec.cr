require "spec"
require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  # Test-only access to the generic type-name substitution seam.  Tuple
  # specializations keep both an aggregate union (`T`) and the original
  # element list (`T__tuple`); splat expansion must use the latter.
  def __test_tuple_splat_substitution(name : String, mapping : Hash(String, String)) : String
    previous = @type_param_map
    @type_param_map = mapping
    @subst_cache_gen &+= 1
    begin
      substitute_type_params_in_type_name(name)
    ensure
      @type_param_map = previous
      @subst_cache_gen &+= 1
    end
  end

  def __test_tuple_splat_type_name(name : String, mapping : Hash(String, String)) : String
    substituted = __test_tuple_splat_substitution(name, mapping)
    get_type_name_from_ref(type_ref_for_name(substituted))
  end

  def __test_block_param_type_names(input_names : Array(String), mapping : Hash(String, String)) : Array(String)
    substitute_block_param_type_names(input_names, mapping)
  end
end

describe "Tuple splat type substitution" do
  it "splices the concrete tuple element list into Union(*T)" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    mapping = {
      "T"        => "Nil | String",
      "T__tuple" => "String, Nil | String, Nil | String",
    }

    substituted = converter.__test_tuple_splat_substitution("Union(*T)", mapping)
    substituted.should eq("Union(String, Nil | String, Nil | String)")
    substituted.should_not contain("*")
    converter.__test_tuple_splat_type_name("Union(*T)", mapping).should_not contain("*")
  end

  it "returns a concrete array from the generic block-parameter path" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    mapping = {
      "T"        => "Nil | String",
      "T__tuple" => "String, Nil | String, Nil | String",
    }

    resolved = converter.__test_block_param_type_names(["Union(*T)", "T"], mapping)
    resolved.should eq(["Union(String, Nil | String, Nil | String)", "Nil | String"])
  end
end
