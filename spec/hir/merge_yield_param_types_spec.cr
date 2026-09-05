require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_merge_yield_param_types(
    left : Array(Adamas::HIR::TypeRef)?,
    right : Array(Adamas::HIR::TypeRef)?,
  ) : Array(Adamas::HIR::TypeRef)?
    merge_yield_param_types(left, right)
  end

  def __test_merge_yield_type_ref_for_name(name : String) : Adamas::HIR::TypeRef
    type_ref_for_name(name)
  end

  def __test_merge_yield_type_name(type_ref : Adamas::HIR::TypeRef) : String
    get_type_name_from_ref(type_ref)
  end
end

describe "AstToHir#merge_yield_param_types" do
  it "keeps nil, empty, and arity mismatch semantics" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    int32 = converter.__test_merge_yield_type_ref_for_name("Int32")
    int64 = converter.__test_merge_yield_type_ref_for_name("Int64")

    left = [int32]
    right = [int64]
    converter.__test_merge_yield_param_types(left, nil).not_nil!.same?(left).should be_true
    converter.__test_merge_yield_param_types(nil, right).not_nil!.same?(right).should be_true
    converter.__test_merge_yield_param_types(nil, nil).should be_nil

    empty_left = [] of Adamas::HIR::TypeRef
    empty_right = [] of Adamas::HIR::TypeRef
    converter.__test_merge_yield_param_types(empty_left, right).not_nil!.same?(right).should be_true
    converter.__test_merge_yield_param_types(left, empty_right).not_nil!.same?(left).should be_true
    converter.__test_merge_yield_param_types(empty_left, empty_right).not_nil!.same?(empty_right).should be_true

    mismatch = [int32, int64]
    converter.__test_merge_yield_param_types(left, mismatch).not_nil!.same?(left).should be_true
    left.should eq([int32])
    right.should eq([int64])
    empty_left.should be_empty
    empty_right.should be_empty
  end

  it "preserves VOID slots and unions concrete slots by index" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    int32 = converter.__test_merge_yield_type_ref_for_name("Int32")
    int64 = converter.__test_merge_yield_type_ref_for_name("Int64")
    void = Adamas::HIR::TypeRef::VOID

    left = [void, int32]
    right = [int64, void]
    merged = converter.__test_merge_yield_param_types(left, right)
    merged.should_not be_nil
    merged.not_nil!.size.should eq(2)
    merged.not_nil![0].should eq(int64)
    merged.not_nil![1].should eq(int32)
    merged.not_nil!.same?(left).should be_false
    merged.not_nil!.same?(right).should be_false
    left.should eq([void, int32])
    right.should eq([int64, void])

    union = converter.__test_merge_yield_param_types([int32], [int64])
    union.should_not be_nil
    converter.__test_merge_yield_type_name(union.not_nil![0]).should eq("Int32 | Int64")
  end
end
