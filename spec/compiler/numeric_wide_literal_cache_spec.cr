require "../spec_helper"
require "../../src/compiler/hir/hir"
require "../../src/compiler/mir/mir"

describe "wide integer literal caches" do
  it "initializes HIR wide caches from narrow source-independent payloads" do
    signed = Adamas::HIR::Literal.new(1_u32, Adamas::HIR::TypeRef::INT128, 1_i64)
    unsigned = Adamas::HIR::Literal.new(2_u32, Adamas::HIR::TypeRef::UINT128, 1_u64)

    signed.int128_value.should eq(1_i128)
    unsigned.uint128_value.should eq(1_u128)
  end

  it "initializes MIR wide caches in direct constants and integer builders" do
    signed = Adamas::MIR::Constant.new(1_u32, Adamas::MIR::TypeRef::INT128, 1_i64)
    unsigned = Adamas::MIR::Constant.new(2_u32, Adamas::MIR::TypeRef::UINT128, 1_u64)

    signed.int128_value.should eq(1_i128)
    unsigned.uint128_value.should eq(1_u128)

    function = Adamas::MIR::Function.new(
      Adamas::MIR::FunctionId.new(1_u32),
      "wide_constant_cache",
      Adamas::MIR::TypeRef::VOID,
    )
    builder = Adamas::MIR::Builder.new(function)
    signed_id = builder.const_int(1_i64, Adamas::MIR::TypeRef::INT128)
    unsigned_id = builder.const_uint(1_u64, Adamas::MIR::TypeRef::UINT128)
    instructions = function.get_block(function.entry_block).instructions
    signed_built = instructions.find { |instruction| instruction.id == signed_id }.not_nil!.as(Adamas::MIR::Constant)
    unsigned_built = instructions.find { |instruction| instruction.id == unsigned_id }.not_nil!.as(Adamas::MIR::Constant)

    signed_built.int128_value.should eq(1_i128)
    unsigned_built.uint128_value.should eq(1_u128)
  end
end
