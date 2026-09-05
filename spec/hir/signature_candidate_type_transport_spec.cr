require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

# Test-only access to the two Set(String) scans used by signature resolution.
class Adamas::HIR::AstToHir
  def __test_pick_signature_candidate(candidates : Set(String), namespace : String) : String?
    pick_short_type_candidate(candidates, namespace)
  end

  def __test_resolve_signature_candidate(name : String, candidates : Set(String)) : String?
    @short_type_index[name] = candidates
    resolve_class_name_in_signature_context(name)
  end
end

describe "signature candidate type transport" do
  it "keeps namespace selection, shortest selection, and empty-set behavior" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)

    converter.__test_pick_signature_candidate(
      Set{"Resolver::LongCandidate", "Resolver::Short"},
      "Resolver"
    ).should eq("Resolver::Short")

    converter.__test_resolve_signature_candidate(
      "Alias",
      Set{"LongAlias", "S"}
    ).should eq("S")

    converter.__test_resolve_signature_candidate("Empty", Set(String).new).should be_nil
  end
end
