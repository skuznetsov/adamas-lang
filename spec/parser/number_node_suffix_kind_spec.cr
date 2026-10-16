require "../spec_helper"
require "../../src/compiler/frontend/ast"

private def suffix_kind_number(text : String, kind : Adamas::Compiler::Frontend::NumberKind)
  Adamas::Compiler::Frontend::NumberNode.new(Adamas::Compiler::Frontend::Span.zero, text.to_slice, kind)
end

describe "NumberNode suffix identity" do
  it "keeps lowercase hexadecimal f digits even when followed by a suffix width" do
    {"0xf0" => 240_u64, "0xf4" => 244_u64, "0xf5" => 245_u64,
     "0xf32" => 3890_u64, "0xf64" => 3940_u64, "0xff32" => 65330_u64,
     "0xff64" => 65380_u64, "0xf0f64" => 986980_u64,
     "0xF0" => 240_u64, "0xf_32" => 3890_u64}.each do |text, expected|
      node = suffix_kind_number(text, Adamas::Compiler::Frontend::NumberKind::I32)
      node.parsed_uint.should eq(expected)
      node.parsed_int.should eq(expected.to_i64)
    end
  end

  it "still strips lexed signed and unsigned suffixes on every radix" do
    {"0xf0_i64", Adamas::Compiler::Frontend::NumberKind::I64, 240_u64}.tap do |entry|
      suffix_kind_number(entry[0], entry[1]).parsed_int.should eq(entry[2].to_i64)
    end
    {"0xf0_u64" => 240_u64, "0xff32u64" => 65330_u64,
     "0b1111_u64" => 15_u64, "0o17u64" => 15_u64,
     "42u64" => 42_u64}.each do |text, expected|
      suffix_kind_number(text, Adamas::Compiler::Frontend::NumberKind::U64).parsed_uint.should eq(expected)
    end
  end

  it "still parses lexed float suffixes with and without an underscore" do
    ["1.25_f32", "1.25f32"].each do |text|
      suffix_kind_number(text, Adamas::Compiler::Frontend::NumberKind::F32).parsed_float.should eq(1.25)
    end
    ["1.25_f64", "1.25f64", "1e2f64"].each do |text|
      expected = text.starts_with?("1e") ? 100.0 : 1.25
      suffix_kind_number(text, Adamas::Compiler::Frontend::NumberKind::F64).parsed_float.should eq(expected)
    end
  end
end
