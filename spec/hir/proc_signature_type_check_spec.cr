require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_proc_signature_check(value : String, target : String) : Bool?
    statically_is_a_type?(type_ref_for_name(value), type_ref_for_name(target))
  end

  def __test_proc_bare_class_check(value : String) : Bool?
    typed = type_ref_for_name(value)
    bare = @module.intern_type(TypeDescriptor.new(TypeKind::Class, "Proc"))
    statically_is_a_type?(typed, bare)
  end

  def __test_proc_union_signature_check(value : String, target : String) : {Array(Int32), Int32}?
    result = union_variants_satisfying_union_check(type_ref_for_name(value), type_ref_for_name(target))
    result.try { |matched, total| {matched.map(&.[0]), total} }
  end

  def __test_proc_union_narrowing(value : String, target : String) : {String, Int32}
    value_type = type_ref_for_name(value)
    target_type = type_ref_for_name(target)
    function = @module.create_function("proc_union_narrowing", TypeRef::NIL)
    parameter = function.add_param("value", value_type)
    ctx = LoweringContext.new(function, @module, @arena)
    ctx.register_type(parameter.id, value_type)
    ctx.register_local("value", parameter.id)
    apply_is_a_narrowing(ctx, [IsANarrowingTarget.new("value", target_type)])
    local = ctx.lookup_local("value").not_nil!
    {generic_param_type_name_from_ref(ctx.type_of(local)), function.blocks.flat_map(&.instructions).count { |instruction| instruction.is_a?(UnionUnwrap) }}
  end
end

private def proc_signature_check_converter : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(""))
  program = parser.parse_program
  Adamas::HIR::AstToHir.new(program.arena)
end

describe "Concrete Proc signature type tests" do
  {
    {"Proc(Nil)", "Proc(Int32)"},
    {"Proc(Int32)", "Proc(String)"},
    {"Proc(Int32, Int32)", "Proc(Int64, Int32)"},
    {"Proc(Int32, Int32)", "Proc(Int32)"},
    {"Proc(Int32, Int32 | String)", "Proc(Int32, Int32)"},
    {"Proc(Nil)", "Proc(Nil | Int32)"},
    {"Proc(Int32)", "Proc(Nil)"},
    {"Proc(Int32, Int32)", "Proc(Int32 | Int64, Int32)"},
  }.each do |value, target|
    it "rejects #{value} as #{target}" do
      proc_signature_check_converter.__test_proc_signature_check(value, target).should be_false
    end
  end

  {"Proc(Nil)", "Proc(Int32)", "Proc(Int32, Int32)", "Proc(Int32, Int32 | String)"}.each do |signature|
    it "accepts identical #{signature}" do
      proc_signature_check_converter.__test_proc_signature_check(signature, signature).should be_true
    end

    it "accepts #{signature} as bare Proc" do
      proc_signature_check_converter.__test_proc_signature_check(signature, "Proc").should be_true
    end

    it "accepts #{signature} against a parsed bare Proc class" do
      proc_signature_check_converter.__test_proc_bare_class_check(signature).should be_true
    end
  end
end


describe "Union Proc signature predicates" do
  it "matches every Proc arm against bare Proc" do
    result = proc_signature_check_converter.__test_proc_union_signature_check("Proc(Nil) | Proc(Int32)", "Proc").not_nil!
    result[0].size.should eq(2)
    result[1].should eq(2)
  end

  it "rejects an absent concrete result signature" do
    result = proc_signature_check_converter.__test_proc_union_signature_check("Proc(Nil) | Proc(Int32)", "Proc(String)").not_nil!
    result[0].should be_empty
    result[1].should eq(2)
  end

  it "matches only the exact concrete signature" do
    result = proc_signature_check_converter.__test_proc_union_signature_check("Proc(Nil) | Proc(Int32)", "Proc(Int32)").not_nil!
    result[0].size.should eq(1)
    result[1].should eq(2)
  end

  it "excludes non-Proc arms from a bare Proc check" do
    result = proc_signature_check_converter.__test_proc_union_signature_check("Proc(Nil) | Tuple(Int32, Int32)", "Proc").not_nil!
    result[0].size.should eq(1)
    result[1].should eq(2)
  end

  it "keeps checked union expansion" do
    result = proc_signature_check_converter.__test_proc_union_signature_check("Proc(Nil) | Proc(Int32)", "Proc(Int32) | Tuple(Int32, Int32)").not_nil!
    result[0].size.should eq(1)
    result[1].should eq(2)
  end

  it "matches multiple Array instantiations against their bare generic" do
    result = proc_signature_check_converter.__test_proc_union_signature_check("Array(Int32) | Array(String)", "Array").not_nil!
    result[0].size.should eq(2)
    result[1].should eq(2)
  end
end


describe "Union Proc predicate branch narrowing" do
  it "keeps all signatures after a bare Proc check" do
    result = proc_signature_check_converter.__test_proc_union_narrowing("Proc(Nil) | Proc(Int32)", "Proc")
    result[0].should contain("Proc(Nil)")
    result[0].should contain("Proc(Int32)")
    result[1].should eq(0)
  end

  it "retains both Proc signatures in a partial intersection" do
    result = proc_signature_check_converter.__test_proc_union_narrowing("Proc(Nil) | Proc(Int32) | Tuple(Int32, Int32)", "Proc")
    result[0].should contain("Proc(Nil)")
    result[0].should contain("Proc(Int32)")
    result[0].should_not contain("Tuple")
    result[1].should eq(0)
  end

  it "unwraps one proven concrete signature" do
    result = proc_signature_check_converter.__test_proc_union_narrowing("Proc(Nil) | Proc(Int32)", "Proc(Int32)")
    result.should eq({"Proc(Int32)", 1})
  end

  it "does not replace an impossible branch with an unrelated Proc" do
    result = proc_signature_check_converter.__test_proc_union_narrowing("Proc(Nil) | Proc(Int32)", "Proc(String)")
    result[0].should contain("Proc(Nil)")
    result[0].should contain("Proc(Int32)")
    result[0].should_not contain("Proc(String)")
    result[1].should eq(0)
  end
end
