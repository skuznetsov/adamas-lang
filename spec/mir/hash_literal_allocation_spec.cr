require "../spec_helper"
require "../../src/compiler/mir/mir"
require "../../src/compiler/mir/hir_to_mir"
require "../../src/compiler/mir/optimizations"
require "../../src/compiler/mir/llvm_backend"

private def hash_literal_allocation_ir(size : UInt64, offset : UInt32?, field_type : Adamas::MIR::TypeRef = Adamas::MIR::TypeRef::UINT8, type_name : String = "Hash(String, Int32)", type_kind : Adamas::MIR::TypeKind = Adamas::MIR::TypeKind::Reference)
  mod = Adamas::MIR::Module.new("hash_literal_layout")
  type = mod.type_registry.create_type(type_kind, type_name, size, 8)
  type.add_field("@indices_bytesize", field_type, offset) if offset
  ref = Adamas::MIR::TypeRef.new(type.id)
  func = mod.create_function("hash_literal_probe", ref)
  builder = Adamas::MIR::Builder.new(func)
  stale_id = builder.const_int(999999, Adamas::MIR::TypeRef::INT32)
  builder.ret(builder.extern_call("__adamas_hash_new", [stale_id], ref))
  gen = Adamas::MIR::LLVMIRGenerator.new(mod)
  gen.emit_type_metadata = false
  {gen.generate, type.id}
end

describe "Hash literal allocation" do
  it "uses the registered body size, type ID and field offset" do
    output, id = hash_literal_allocation_ir(56_u64, 32_u32)
    body = output[/define ptr @hash_literal_probe\([^\n]*\)\s*\{.*?\n\}/m].not_nil!
    body.should contain("call ptr @__adamas_hash_new(i32 #{id}, i64 56, i32 32)")
    helper = output[/define ptr @__adamas_hash_new\([^\n]*\)\s*\{.*?\n\}/m].not_nil!
    helper.should contain("add i64 %body_size, 8")
    helper.should contain("store i64 9223372036854775807")
    helper.should contain("getelementptr i8, ptr %raw, i64 8")
    helper.should contain("i64 %body_size, i1 false)")
  end

  it "does not assume a 56-byte body or offset 32" do
    output, id = hash_literal_allocation_ir(80_u64, 64_u32)
    output.should contain("call ptr @__adamas_hash_new(i32 #{id}, i64 80, i32 64)")
  end

  it "accepts signed one-byte initialization metadata" do
    output, id = hash_literal_allocation_ir(56_u64, 32_u32, Adamas::MIR::TypeRef::INT8)
    output.should contain("call ptr @__adamas_hash_new(i32 #{id}, i64 56, i32 32)")
  end

  it "rejects missing field layout instead of falling back to 48 bytes" do
    expect_raises(Exception, /Hash literal.*layout/) do
      hash_literal_allocation_ir(56_u64, nil)
    end
  end

  it "rejects a non-byte initialization field" do
    expect_raises(Exception, /Hash literal.*layout/) do
      hash_literal_allocation_ir(56_u64, 32_u32, Adamas::MIR::TypeRef::UINT32)
    end
  end

  it "rejects a signed field wider than one byte" do
    expect_raises(Exception, /Hash literal.*layout/) do
      hash_literal_allocation_ir(56_u64, 32_u32, Adamas::MIR::TypeRef::INT16)
    end
  end

  it "rejects an initialization field overlapping the type header" do
    expect_raises(Exception, /Hash literal.*layout/) do
      hash_literal_allocation_ir(56_u64, 0_u32)
    end
  end

  it "rejects an initialization field outside the registered body" do
    expect_raises(Exception, /Hash literal.*layout/) do
      hash_literal_allocation_ir(32_u64, 32_u32)
    end
  end
  it "accepts the globally qualified Hash class name" do
    output, id = hash_literal_allocation_ir(56_u64, 32_u32, type_name: "::Hash(String, Int32)")
    output.should contain("call ptr @__adamas_hash_new(i32 #{id}, i64 56, i32 32)")
  end

  it "still rejects invalid layout for a globally qualified Hash" do
    expect_raises(Exception, /Hash literal invalid indices field layout/) do
      hash_literal_allocation_ir(32_u64, 32_u32, type_name: "::Hash(String, Int32)")
    end
  end

  it "does not admit a namespaced class merely named Hash" do
    ["Other::Hash(String, Int32)", "::Other::Hash(String, Int32)", "HashLike(String, Int32)"].each do |name|
      expect_raises(Exception, /Hash literal missing concrete reference layout/) do
        hash_literal_allocation_ir(56_u64, 32_u32, type_name: name)
      end
    end
  end

  it "does not admit a non-reference globally qualified Hash" do
    expect_raises(Exception, /Hash literal missing concrete reference layout/) do
      hash_literal_allocation_ir(56_u64, 32_u32, type_name: "::Hash(String, Int32)", type_kind: Adamas::MIR::TypeKind::Struct)
    end
  end

end
