require "../spec_helper"
require "../../src/compiler/hir/hir"

describe Adamas::HIR::Literal do
  it "preserves a high-bit unsigned enum payload carried through signed metadata" do
    value = 0xf000000000000043_u64
    literal = Adamas::HIR::Literal.new(0_u32, Adamas::HIR::TypeRef::UINT64, value.to_i64!)
    literal.to_s.should contain(value.to_s)
    literal.uint_value.should eq(value)
  end

  it "preserves a negative signed payload when integer storage changes views" do
    literal = Adamas::HIR::Literal.new(0_u32, Adamas::HIR::TypeRef::INT64, UInt64::MAX)
    literal.int_value.should eq(-1_i64)
    literal.to_s.should contain("literal -1 : Int64")
  end
end
