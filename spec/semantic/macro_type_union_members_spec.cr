require "spec"
require "../../src/compiler/semantic/context"
require "../../src/compiler/semantic/macro_value"

describe "TypeNode union_types" do
  it "returns a singleton TypeNode collection for a non-union type" do
    type = Adamas::Compiler::Semantic::MacroTypeValue.new("UInt8")
    members = type.call_method("union_types", [] of Adamas::Compiler::Semantic::MacroValue, nil)
    members.class_name.should eq("ArrayLiteral")
    members.call_method("size", [] of Adamas::Compiler::Semantic::MacroValue, nil).to_macro_output.should eq("1")
    members.call_method("includes?", [type.as(Adamas::Compiler::Semantic::MacroValue)], nil).truthy?.should be_true
  end

  it "exposes concrete members rather than a rendered union identifier" do
    type = Adamas::Compiler::Semantic::MacroTypeValue.new("Int32 | String")
    members = type.call_method("union_types", [] of Adamas::Compiler::Semantic::MacroValue, nil)
    members.class_name.should eq("ArrayLiteral")
    members.call_method("size", [] of Adamas::Compiler::Semantic::MacroValue, nil).to_macro_output.should eq("2")
    members.call_method("includes?", [Adamas::Compiler::Semantic::MacroTypeValue.new("Int32").as(Adamas::Compiler::Semantic::MacroValue)], nil).truthy?.should be_true
    members.call_method("includes?", [Adamas::Compiler::Semantic::MacroTypeValue.new("UInt8").as(Adamas::Compiler::Semantic::MacroValue)], nil).truthy?.should be_false
  end

  it "does not split a union inside generic arguments" do
    type = Adamas::Compiler::Semantic::MacroTypeValue.new("Array(Int32 | String)")
    members = type.call_method("union_types", [] of Adamas::Compiler::Semantic::MacroValue, nil)
    members.call_method("size", [] of Adamas::Compiler::Semantic::MacroValue, nil).to_macro_output.should eq("1")
    members.call_method("includes?", [type.as(Adamas::Compiler::Semantic::MacroValue)], nil).truthy?.should be_true
  end

  it "rejects arguments to the zero-argument union_types method" do
    type = Adamas::Compiler::Semantic::MacroTypeValue.new("UInt8")
    extra = Adamas::Compiler::Semantic::MacroNumberValue.new(1_i64).as(Adamas::Compiler::Semantic::MacroValue)
    expect_raises(ArgumentError) do
      type.call_method("union_types", [extra], nil)
    end
    expect_raises(ArgumentError) do
      type.call_method("union_types", [] of Adamas::Compiler::Semantic::MacroValue, {"extra" => extra})
    end
  end

  it "does not treat Nil inside a generic argument as outer nilability" do
    type = Adamas::Compiler::Semantic::MacroTypeValue.new("Array(Nil | String)")
    type.call_method("nilable?", [] of Adamas::Compiler::Semantic::MacroValue, nil).truthy?.should be_false
  end

  it "rejects arguments to the other zero-argument type reflection methods" do
    type = Adamas::Compiler::Semantic::MacroTypeValue.new("UInt8")
    extra = Adamas::Compiler::Semantic::MacroNumberValue.new(1_i64).as(Adamas::Compiler::Semantic::MacroValue)
    {"nilable?", "union?", "type_vars"}.each do |method|
      expect_raises(ArgumentError) do
        type.call_method(method, [extra], nil)
      end
      expect_raises(ArgumentError) do
        type.call_method(method, [] of Adamas::Compiler::Semantic::MacroValue, {"extra" => extra})
      end
    end
  end
end
