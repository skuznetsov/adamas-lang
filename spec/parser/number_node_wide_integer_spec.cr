require "spec"
require "../../src/compiler/frontend/parser"

private def wide_integer_node(text : String, kind : Adamas::Compiler::Frontend::NumberKind)
  Adamas::Compiler::Frontend::NumberNode.new(
    Adamas::Compiler::Frontend::Span.zero,
    text.to_slice,
    kind,
  )
end

describe "NumberNode wide integer payloads" do
  it "retains signed 128-bit decimal boundaries" do
    wide_integer_node(
      "170141183460469231731687303715884105727_i128",
      Adamas::Compiler::Frontend::NumberKind::I128,
    ).parsed_int128.should eq(Int128::MAX)

    wide_integer_node(
      "-170141183460469231731687303715884105728_i128",
      Adamas::Compiler::Frontend::NumberKind::I128,
    ).parsed_int128.should eq(Int128::MIN)
  end

  it "retains unsigned 128-bit maximum across radices" do
    wide_integer_node(
      "340282366920938463463374607431768211455_u128",
      Adamas::Compiler::Frontend::NumberKind::U128,
    ).parsed_uint128.should eq(UInt128::MAX)

    wide_integer_node(
      "0xffffffffffffffffffffffffffffffff_u128",
      Adamas::Compiler::Frontend::NumberKind::U128,
    ).parsed_uint128.should eq(UInt128::MAX)

    binary_2_64 = "0b1" + "0" * 64 + "_u128"
    wide_integer_node(binary_2_64, Adamas::Compiler::Frontend::NumberKind::U128).parsed_uint128.should eq(0x10000000000000000_u128)

    octal_2_64 = "0o2" + "0" * 21 + "_u128"
    wide_integer_node(octal_2_64, Adamas::Compiler::Frontend::NumberKind::U128).parsed_uint128.should eq(0x10000000000000000_u128)
  end

  it "reports overflowing and malformed wide values instead of caching zero silently" do
    overflow_i128 = wide_integer_node(
      "170141183460469231731687303715884105728_i128",
      Adamas::Compiler::Frontend::NumberKind::I128,
    )
    overflow_i128.integer_parse_error.not_nil!.should contain("Int128")

    overflow_u128 = wide_integer_node(
      "340282366920938463463374607431768211456_u128",
      Adamas::Compiler::Frontend::NumberKind::U128,
    )
    overflow_u128.integer_parse_error.not_nil!.should contain("UInt128")

    malformed = wide_integer_node("0x_u128", Adamas::Compiler::Frontend::NumberKind::U128)
    malformed.integer_parse_error.should_not be_nil
  end

  it "surfaces wide parse failures through Parser diagnostics" do
    parser = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new("value = 340282366920938463463374607431768211456_u128")
    )
    parser.parse_program
    parser.diagnostics.map(&.message).join("\n").should contain("UInt128")
  end
end
