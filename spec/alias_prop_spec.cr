require "spec"
require "../src/compiler/mir/mir"

describe "RC operands" do
  it "includes ptr operand for RC ops" do
    func = Adamas::MIR::Function.new(0_u32, "test", Adamas::MIR::TypeRef::VOID)
    builder = Adamas::MIR::Builder.new(func)
    ptr = builder.const_nil
    inc = Adamas::MIR::RCIncrement.new(func.next_value_id, ptr, false)
    dec = Adamas::MIR::RCDecrement.new(func.next_value_id, ptr, false)
    inc.operands.should eq [ptr]
    dec.operands.should eq [ptr]
  end
end
