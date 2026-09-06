require "../spec_helper"
require "../../src/compiler/mir/mir"
require "../../src/compiler/mir/hir_to_mir"
require "../../src/compiler/mir/optimizations"
require "../../src/compiler/mir/llvm_backend"

private def wrap_probe_union(mod, name, refs)
  type = mod.type_registry.create_type(Adamas::MIR::TypeKind::Union, name, 16, 8)
  ref = Adamas::MIR::TypeRef.new(type.id)
  variants = refs.map do |member|
    t = mod.type_registry.get(member).not_nil!
    type.add_variant(t)
    Adamas::MIR::UnionVariantDescriptor.new(member.id.to_i32, member, t.name, t.size.to_i32, t.alignment.to_i32, nil)
  end
  mod.register_union(ref, Adamas::MIR::UnionDescriptor.new(name, variants, 16, 8))
  ref
end

describe "UnionWrap actual representation" do
  it "transfers a completed union call result despite a scalar wrap hint" do
    mod = Adamas::MIR::Module.new("late_union_wrap")
    src = wrap_probe_union(mod, "Nil | Int32", [Adamas::MIR::TypeRef::NIL, Adamas::MIR::TypeRef::INT32])
    dst = wrap_probe_union(mod, "Nil | Int32 | Float64", [Adamas::MIR::TypeRef::NIL, Adamas::MIR::TypeRef::INT32, Adamas::MIR::TypeRef::FLOAT64])
    callee = mod.create_function("late_union_source", src)
    callee.add_param("value", src)
    Adamas::MIR::Builder.new(callee).ret(0_u32)
    caller = mod.create_function("late_union_wrap", dst)
    caller.add_param("value", src)
    builder = Adamas::MIR::Builder.new(caller)
    value = builder.call(callee.id, [0_u32], Adamas::MIR::TypeRef::INT32)
    wrapped = builder.union_wrap(value, Adamas::MIR::TypeRef::INT32.id.to_i32, dst)
    builder.ret(wrapped)
    gen = Adamas::MIR::LLVMIRGenerator.new(mod)
    gen.emit_type_metadata = false
    output = gen.generate
    body = output[/define [^\n]* @late_union_wrap\([^\n]*\)\s*\{.*?\n\}/m].not_nil!
    body.should contain(".u2u_src_tid = load i32")
    body.should match(/store i32 %r\d+\.u2u_src_tid, ptr %r\d+\.u2u_dst_tid_ptr/)
    body.should contain("i64 8, i1 false)")
    body.should_not match(/store %[^ ]+\.union %r\d+, ptr %r\d+\.payload_ptr/)
  end

  it "passes through identical unions and preserves explicit nested variants" do
    mod = Adamas::MIR::Module.new("union_wrap_controls")
    src = wrap_probe_union(mod, "Nil | Int32", [Adamas::MIR::TypeRef::NIL, Adamas::MIR::TypeRef::INT32])
    nested = wrap_probe_union(mod, "NestedOrFloat", [src, Adamas::MIR::TypeRef::FLOAT64])
    same = mod.create_function("same_union_wrap", src)
    same.add_param("value", src)
    builder = Adamas::MIR::Builder.new(same)
    builder.ret(builder.union_wrap(0_u32, Adamas::MIR::TypeRef::INT32.id.to_i32, src))
    outer = mod.create_function("nested_union_wrap", nested)
    outer.add_param("value", src)
    builder = Adamas::MIR::Builder.new(outer)
    builder.ret(builder.union_wrap(0_u32, src.id.to_i32, nested))
    gen = Adamas::MIR::LLVMIRGenerator.new(mod)
    gen.emit_type_metadata = false
    output = gen.generate
    same_body = output[/define [^\n]* @same_union_wrap\([^\n]*\)\s*\{.*?\n\}/m].not_nil!
    same_body.should contain(".passthru = alloca")
    same_body.should_not contain(".payload_ptr")
    nested_body = output[/define [^\n]* @nested_union_wrap\([^\n]*\)\s*\{.*?\n\}/m].not_nil!
    nested_body.should contain("store %Nil$_$OR$_Int32.union %value, ptr %r1.payload_ptr")
    nested_body.should_not contain(".u2u_src")
  end

  it "copies the full wide payload for both ordinary and explicit transfer hints" do
    mod = Adamas::MIR::Module.new("wide_union_wrap")
    src = wrap_probe_union(mod, "Nil | Int128", [Adamas::MIR::TypeRef::NIL, Adamas::MIR::TypeRef::INT128])
    dst = wrap_probe_union(mod, "Nil | Int128 | Float64", [Adamas::MIR::TypeRef::NIL, Adamas::MIR::TypeRef::INT128, Adamas::MIR::TypeRef::FLOAT64])
    [Adamas::MIR::TypeRef::INT128.id.to_i32, -2].each_with_index do |hint, i|
      func = mod.create_function("wide_union_wrap_#{i}", dst)
      func.add_param("value", src)
      builder = Adamas::MIR::Builder.new(func)
      builder.ret(builder.union_wrap(0_u32, hint, dst))
    end
    gen = Adamas::MIR::LLVMIRGenerator.new(mod)
    gen.emit_type_metadata = false
    output = gen.generate
    2.times do |i|
      body = output[/define [^\n]* @wide_union_wrap_#{i}\([^\n]*\)\s*\{.*?\n\}/m].not_nil!
      body.should contain("i64 16, i1 false)")
      body.should contain(".u2u_src_tid = load i32")
      body.should_not match(/store %[^ ]+\.union %value, ptr %r\d+\.payload_ptr/)
    end
  end
end
