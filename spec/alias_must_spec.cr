require "../spec_helper"

describe "must alias scaffolding" do
  it "exposes must_alias_with on HIR Value" do
    lit = Adamas::HIR::Literal.new(0_u32, Adamas::HIR::TypeRef::INT32, 1_i64)
    lit.must_alias_with.should be_nil
  end

  it "initializes must_alias set in RCElisionPass" do
    func = Adamas::MIR::Function.new(0_u32, "test", Adamas::MIR::TypeRef::VOID)
    pass = Adamas::MIR::RCElisionPass.new(func)
    pass.run.should eq(0)
    pass.must_alias.should_not be_nil
  end
end
