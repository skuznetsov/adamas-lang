require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_known_recursive_macro_receiver(name : String, aliases : Hash(String, String)) : Bool
    aliases.each { |key, value| register_type_alias(key, value) }
    known_macro_type_receiver_name?(name)
  end
end

private def known_recursive_macro_receiver(name : String, aliases = {} of String => String)
  converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
  converter.__test_known_recursive_macro_receiver(name, aliases)
end

describe "Macro type receiver validation of recursive aliases" do
  it "admits a recursive alias through Array and Hash generic arguments" do
    known_recursive_macro_receiver("RecursiveField", {
      "RecursiveField" => "Nil | Array(RecursiveField) | Hash(String, RecursiveField)",
    }).should be_true
  end

  it "admits mutually recursive registered aliases" do
    known_recursive_macro_receiver("LeftField", {
      "LeftField" => "Nil | Array(RightField)",
      "RightField" => "String | Hash(String, LeftField)",
    }).should be_true
  end

  it "still checks an unknown union member after visiting a recursive edge" do
    known_recursive_macro_receiver("BrokenField", {
      "BrokenField" => "Array(BrokenField) | MissingMacroType",
    }).should be_false
  end

  it "rejects an unknown generic base containing the recursive alias" do
    known_recursive_macro_receiver("BrokenField", {
      "BrokenField" => "MissingMacroType(BrokenField) | Nil",
    }).should be_false
  end

  it "validates NamedTuple field values without treating keys as types" do
    known_recursive_macro_receiver("RecordField", {
      "RecordField" => "Nil | Array(NamedTuple(value: RecordField, label: String))",
    }).should be_true
  end

  it "rejects an unknown NamedTuple field value after a recursive field" do
    known_recursive_macro_receiver("RecordField", {
      "RecordField" => "Nil | Array(NamedTuple(value: RecordField, missing: MissingMacroType))",
    }).should be_false
  end

  it "validates Union generic syntax and its recursive members" do
    known_recursive_macro_receiver("Union(Int32, RecursiveField)", {
      "RecursiveField" => "Nil | Array(RecursiveField)",
    }).should be_true
    known_recursive_macro_receiver("Union(Int32, MissingMacroType)").should be_false
  end

  it "keeps unknown unbound parameters and unnamed NamedTuple arguments invalid" do
    known_recursive_macro_receiver("Array(T)").should be_false
    known_recursive_macro_receiver("NamedTuple(Int32)").should be_false
    known_recursive_macro_receiver("Array(Int32) | Array(MissingMacroType)").should be_false
  end
end
