require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_recursive_macro_projection(name : String, aliases : Hash(String, String))
    aliases.each { |key, value| register_type_alias(key, value) }
    macro_value_for_type_name(name).as(Adamas::Compiler::Semantic::MacroTypeValue)
  end

  def __test_recursive_macro_alias_boundaries(aliases : Hash(String, String))
    aliases.each { |key, value| register_type_alias(key, value) }
    macro_recursive_alias_names.to_a.sort
  end
end

describe "Macro type value projection of recursive aliases" do
  it "preserves a recursive alias as a finite generic argument TypeNode" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    value = converter.__test_recursive_macro_projection("Array(RecursiveField)", {
      "RecursiveField" => "Nil | Array(RecursiveField) | Hash(String, RecursiveField)",
    })
    args = value.type_var_values.not_nil!
    args.size.should eq(1)
    arg = args.first.as(Adamas::Compiler::Semantic::MacroTypeValue)
    arg.name.should eq("RecursiveField")
    arg.call_method("union?", [] of Adamas::Compiler::Semantic::MacroValue, nil).to_macro_output.should eq("false")
    arg.call_method("class?", [] of Adamas::Compiler::Semantic::MacroValue, nil).to_macro_output.should eq("false")
    arg.call_method("nilable?", [] of Adamas::Compiler::Semantic::MacroValue, nil).to_macro_output.should eq("true")
    arg.call_method("union_types", [] of Adamas::Compiler::Semantic::MacroValue, nil).as(Adamas::Compiler::Semantic::MacroArrayValue).elements.size.should eq(1)
    value.display_name.should eq("Array(RecursiveField)")
  end

  it "still resolves an ordinary non-recursive alias in a generic argument" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    value = converter.__test_recursive_macro_projection("Array(SimpleField)", {
      "SimpleField" => "Int32",
    })
    value.type_var_values.not_nil!.first.as(Adamas::Compiler::Semantic::MacroTypeValue).name.should eq("Int32")
  end

  it "expands a non-recursive alias that refers to a recursive alias" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    value = converter.__test_recursive_macro_projection("Array(OtherField)", {
      "RecursiveField" => "Nil | Array(RecursiveField)",
      "OtherField" => "RecursiveField",
    })
    value.display_name.should eq("Array(Array(RecursiveField) | Nil)")
  end

  it "preserves only the cycle-closing alias in mutually recursive declarations" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    aliases = {
      "LeftField" => "Nil | Array(RightField)",
      "RightField" => "Hash(String, LeftField)",
    }
    converter.__test_recursive_macro_projection("Array(LeftField)", aliases).display_name.should eq("Array(LeftField)")
    converter.__test_recursive_macro_projection("Array(RightField)", aliases).display_name.should eq("Array(Hash(String, LeftField))")
  end

  it "discovers a cycle through NamedTuple field values" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    value = converter.__test_recursive_macro_projection("Array(RecordField)", {
      "RecordField" => "Nil | Array(NamedTuple(value: RecordField, label: String))",
    })
    value.display_name.should eq("Array(RecordField)")
  end

  it "uses an alias declaration namespace for recursive references" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    value = converter.__test_recursive_macro_projection("Array(Outer::Field)", {
      "Field" => "Int32",
      "Outer::Field" => "Nil | Array(Field)",
    })
    value.display_name.should eq("Array(Outer::Field)")
  end


  it "invalidates recursive identity discovery when a later alias closes a cycle" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_recursive_macro_alias_boundaries({"LeftField" => "Array(RightField)"}).should be_empty
    converter.__test_recursive_macro_alias_boundaries({"RightField" => "Hash(String, LeftField)"}).should eq(["LeftField"])
  end


  it "does not expand nominal identity entries in the shared alias registry" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_recursive_macro_alias_boundaries({"Int32" => "Int32"}).should be_empty
    value = converter.__test_recursive_macro_projection("Array(Int32)", {} of String => String)
    value.type_var_values.not_nil!.first.as(Adamas::Compiler::Semantic::MacroTypeValue).name.should eq("Int32")
  end


  it "expands alias targets relative to their declaration namespace" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    value = converter.__test_recursive_macro_projection("Array(Outer::OtherField)", {
      "Field" => "Int32",
      "Outer::Field" => "Nil | Array(Field)",
      "Outer::OtherField" => "Field",
    })
    value.display_name.should eq("Array(Array(Outer::Field) | Nil)")
  end

end
