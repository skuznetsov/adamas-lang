require "spec"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_bottom_union_name(name : String) : String
    get_type_name_from_ref(type_ref_for_name(name))
  end
  def __test_bottom_union_pair(left : String, right : String) : String
    get_type_name_from_ref(union_type_for_values(type_ref_for_name(left), type_ref_for_name(right)))
  end
  def __test_bottom_union_set(names : Array(String)) : String
    get_type_name_from_ref(union_type_for_value_set(names.map { |name| type_ref_for_name(name) }).not_nil!)
  end
end

describe "NoReturn value-type joins" do
  it "drops bottom from textual unions in either order" do
    c = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    c.__test_bottom_union_name("Int64 | NoReturn").should eq("Int64")
    c.__test_bottom_union_name("NoReturn | Int64").should eq("Int64")
    3.times do
      c.__test_bottom_union_name("Int64 | NoReturn").should eq("Int64")
      c.__test_bottom_union_name("NoReturn | Int64").should eq("Int64")
    end
  end
  it "preserves an all-bottom join as bottom" do
    c = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    c.__test_bottom_union_name("NoReturn | NoReturn").should eq("NoReturn")
    c.__test_bottom_union_pair("NoReturn", "NoReturn").should eq("NoReturn")
    c.__test_bottom_union_set(["NoReturn", "NoReturn"]).should eq("NoReturn")
  end
  it "uses the same canonicalization for binary and n-ary value joins" do
    c = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    c.__test_bottom_union_pair("Int64", "NoReturn").should eq("Int64")
    c.__test_bottom_union_pair("NoReturn", "Int64").should eq("Int64")
    c.__test_bottom_union_set(["NoReturn", "Int64", "Nil"]).should eq("Nil | Int64")
  end
  it "canonicalizes nested generic arguments without flattening their container" do
    c = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    c.__test_bottom_union_name("Tuple(Int64 | NoReturn)").should eq("Tuple(Int64)")
    c.__test_bottom_union_name("Tuple(NoReturn) | Int64").should eq("Int64 | Tuple(NoReturn)")
  end
  it "retains real alternatives and nominal types named NoReturn" do
    c = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    c.__test_bottom_union_name("Int64 | String").should eq("Int64 | String")
    c.__test_bottom_union_name("Int64 | Shadow::NoReturn").should eq("Int64 | Shadow::NoReturn")
  end
end
