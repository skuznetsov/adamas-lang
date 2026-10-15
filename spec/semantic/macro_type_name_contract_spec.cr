require "spec"
require "../../src/compiler/semantic/context"
require "../../src/compiler/semantic/macro_value"

private alias TypeNameMacroValue = Adamas::Compiler::Semantic::MacroValue
private alias TypeNameMacroType = Adamas::Compiler::Semantic::MacroTypeValue

describe "TypeNode name contract" do
  it "formats unions according to their structural position" do
    nullable = TypeNameMacroType.new("Nil | String")
    array = TypeNameMacroType.new("Array(Nil | String)")
    nested = TypeNameMacroType.new("Array(Array(Nil | String))")

    nullable.call_method("name", [] of TypeNameMacroValue, nil).to_id.should eq("(String | Nil)")
    array.call_method("name", [] of TypeNameMacroValue, nil).to_id.should eq("Array(String | Nil)")
    nested.call_method("name", [] of TypeNameMacroValue, nil).to_id.should eq("Array(Array(String | Nil))")
    nullable.stringify.should eq("(String | Nil)")
    nullable.to_macro_output.should eq("(String | Nil)")
    array.to_macro_output.should eq("Array(String | Nil)")
    nested.to_macro_output.should eq("Array(Array(String | Nil))")
  end

  it "uses resolved generic arguments without changing type identity" do
    type = TypeNameMacroType.new("Array(DuplicateInt)",
      type_vars: ["DuplicateInt"],
      type_var_values: [TypeNameMacroType.new("Int32").as(TypeNameMacroValue)])
    type.call_method("name", [] of TypeNameMacroValue, nil).to_id.should eq("Array(Int32)")
    type.name.should eq("Array(DuplicateInt)")
    no_args = {"generic_args" => Adamas::Compiler::Semantic::MacroBoolValue.new(false).as(TypeNameMacroValue)}
    type.call_method("name", [] of TypeNameMacroValue, no_args).to_id.should eq("Array")
  end

  it "sorts outer union arms by their reflected nested type names" do
    canonical = "Array(Bool) | Array(Nil | Zed) | Array(String)"
    type = TypeNameMacroType.new(canonical)
    expected = "(Array(Bool) | Array(String) | Array(Zed | Nil))"
    type.call_method("name", [] of TypeNameMacroValue, nil).to_id.should eq(expected)
    type.stringify.should eq(expected)
    type.to_macro_output.should eq(expected)
    type.name.should eq(canonical)

    reversed = TypeNameMacroType.new("Array(String) | Array(Nil | Zed) | Array(Bool)")
    reversed.to_macro_output.should eq(expected)
  end

  it "validates positional, named and BoolLiteral option arguments" do
    type = TypeNameMacroType.new("String")
    flag = Adamas::Compiler::Semantic::MacroBoolValue.new(true).as(TypeNameMacroValue)
    expect_raises(ArgumentError, "wrong number of arguments for macro 'TypeNode#name'") do
      type.call_method("name", [flag], nil)
    end
    expect_raises(ArgumentError, "no parameter named 'extra'") do
      type.call_method("name", [] of TypeNameMacroValue, {"extra" => flag})
    end
    text = Adamas::Compiler::Semantic::MacroStringValue.new("yes").as(TypeNameMacroValue)
    expect_raises(ArgumentError, "named argument 'generic_args' to TypeNode#name must be a BoolLiteral, not StringLiteral") do
      type.call_method("name", [] of TypeNameMacroValue, {"generic_args" => text})
    end
  end
end
