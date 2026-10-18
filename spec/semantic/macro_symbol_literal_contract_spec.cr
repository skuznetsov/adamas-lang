require "spec"
require "../../src/compiler/semantic/context"
require "../../src/compiler/semantic/macro_value"

private alias SymbolLiteralMacroValue = Adamas::Compiler::Semantic::MacroValue
private alias SymbolLiteralMacroSymbol = Adamas::Compiler::Semantic::MacroSymbolValue

describe "SymbolLiteral source and semantic name boundary" do
  it "renders source tokens as semantic symbols and identifiers" do
    value = SymbolLiteralMacroSymbol.from_literal(":north")
    value.to_id.should eq("north")
    value.to_macro_output.should eq(":north")
    value.stringify.should eq(":north")
    value.call_method("id", [] of SymbolLiteralMacroValue, nil).to_id.should eq("north")

    operator = SymbolLiteralMacroSymbol.from_literal(":+")
    operator.to_id.should eq("+")
    operator.to_macro_output.should eq(":+")
  end

  it "preserves a colon that belongs to a constructed semantic name" do
    value = SymbolLiteralMacroSymbol.new(":semantic")
    value.to_id.should eq(":semantic")
    value.call_method("id", [] of SymbolLiteralMacroValue, nil).to_id.should eq(":semantic")
  end
end
