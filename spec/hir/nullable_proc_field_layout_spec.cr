require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def spec_early_union_field_size(name : String) : Int32
    hir_union_ivar_storage_size(name)
  end
end

private def early_union_field_size(name : String) : Int32
  parsed = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new("")
  ).parse_program
  Adamas::HIR::AstToHir.new(parsed.arena).spec_early_union_field_size(name)
end

describe "early nullable Proc field storage" do
  ["Proc(Int32, Nil)", "(Int32 -> Nil)", "Int32 -> Nil", "Proc"].each do |arm|
    it "reserves a tag for #{arm}" do
      early_union_field_size("Nil | #{arm}").should be > 8
    end
  end

  it "reserves a tag for the Hash callback with a nested nullable tuple key" do
    early_union_field_size("Nil | (Hash::self, Tuple(UInt64, UInt64, Nil | String) -> Nil)").should be > 8
  end

  it "keeps references containing callback type arguments pointer-sized" do
    ["String", "Array(Proc(Int32, Nil))", "Array((Int32 -> Nil))"].each do |arm|
      early_union_field_size("Nil | #{arm}").should eq(8)
    end
  end

  it "preserves raw nullable pointer and tagged primitive controls" do
    early_union_field_size("Nil | Pointer(UInt8)").should eq(8)
    early_union_field_size("Nil | Int32").should be > 8
  end
end
