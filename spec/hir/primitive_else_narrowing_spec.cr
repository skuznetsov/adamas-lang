require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_else_narrowing(
    source_name : String,
    target_name : String,
    local_name : String = "value",
  ) : {String, String, Bool}
    source_type = type_ref_for_name(source_name)
    target_type = type_ref_for_name(target_name)
    function = @module.create_function("__else_narrow_probe_#{@module.functions.size}", TypeRef::VOID)
    parameter = function.add_param(local_name, source_type)
    context = LoweringContext.new(function, @module, @arena)
    context.register_type(parameter.id, source_type)
    context.register_local(local_name, parameter.id)

    before = generic_param_type_name_from_ref(context.type_of(parameter.id))
    apply_is_a_else_narrowing(context, [IsANarrowingTarget.new(local_name, target_type)])
    narrowed_id = context.lookup_local(local_name).not_nil!
    after = generic_param_type_name_from_ref(context.type_of(narrowed_id))
    {before, after, narrowed_id == parameter.id}
  end
end

private def primitive_else_narrowing_converter : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    class ElseNarrowOwner
    end
    CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  parsed = parser.parse_program
  converter = Adamas::HIR::AstToHir.new(parsed.arena)
  parsed.roots.each do |expr|
    case node = parsed.arena[expr]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    end
  end
  converter
end

describe "primitive is_a? else-branch narrowing" do
  it "narrows Bool | Char to Char when the checked target is Bool" do
    before, after, same_value = primitive_else_narrowing_converter.__test_else_narrowing("Bool | Char", "Bool")
    before.should eq("Bool | Char")
    after.should eq("Char")
    same_value.should be_false
  end

  it "narrows UInt32 | UInt64 to UInt64 when the checked target is UInt32" do
    before, after, same_value = primitive_else_narrowing_converter.__test_else_narrowing("UInt32 | UInt64", "UInt32")
    before.should eq("UInt32 | UInt64")
    after.should eq("UInt64")
    same_value.should be_false
  end

  it "narrows Nil | Bool to Bool when the checked target is Nil" do
    before, after, same_value = primitive_else_narrowing_converter.__test_else_narrowing("Nil | Bool", "Nil")
    before.should eq("Nil | Bool")
    after.should eq("Bool")
    same_value.should be_false
  end

  it "retains the nominal arm when a primitive is excluded from a class union" do
    before, after, same_value = primitive_else_narrowing_converter.__test_else_narrowing("ElseNarrowOwner | Bool", "Bool")
    before.should eq("Bool | ElseNarrowOwner")
    after.should eq("ElseNarrowOwner")
    same_value.should be_false
  end

  it "retains the primitive arm when the class is excluded from a class union" do
    before, after, same_value = primitive_else_narrowing_converter.__test_else_narrowing("ElseNarrowOwner | Bool", "ElseNarrowOwner")
    before.should eq("Bool | ElseNarrowOwner")
    after.should eq("Bool")
    same_value.should be_false
  end

  it "keeps a multi-variant remainder conservative" do
    before, after, same_value = primitive_else_narrowing_converter.__test_else_narrowing("Bool | Char | Int32", "Bool")
    after.should eq(before)
    same_value.should be_true
  end
end
