require "../spec_helper"
require "../../src/compiler/mir/mir"
require "../../src/compiler/mir/optimizations"

module Adamas::MIR
  describe "declared field storage through copy propagation" do
    it "preserves the field type when replacing the stored value" do
      mod = Module.new("store_field_contract")
      function = mod.create_function("store_value", TypeRef::VOID)
      pointer = function.add_param("destination", TypeRef::POINTER)
      builder = Builder.new(function)
      condition = builder.const_bool(true)
      value = builder.const_int(7_i64, TypeRef::INT32)
      other = builder.const_int(9_i64, TypeRef::INT32)
      selected = builder.select(condition, value, other, TypeRef::INT32)
      store = Store.new(builder.next_id, pointer, selected)
      store.field_type = TypeRef.new(400_u32)
      builder.emit(store)
      builder.ret(nil)

      CopyPropagationPass.new(function).run.should be > 0

      rewritten = function.get_block(function.entry_block).instructions
        .find { |instruction| instruction.is_a?(Store) }.not_nil!.as(Store)
      rewritten.value.should eq(value)
      rewritten.field_type.should eq(TypeRef.new(400_u32))
    end

    it "preserves the field type when replacing the destination pointer" do
      mod = Module.new("store_pointer_contract")
      function = mod.create_function("store_pointer", TypeRef::VOID)
      pointer = function.add_param("destination", TypeRef::POINTER)
      other_pointer = function.add_param("other", TypeRef::POINTER)
      builder = Builder.new(function)
      condition = builder.const_bool(true)
      selected = builder.select(condition, pointer, other_pointer, TypeRef::POINTER)
      value = builder.const_int(7_i64, TypeRef::INT32)
      store = Store.new(builder.next_id, selected, value)
      store.field_type = TypeRef::INT64
      builder.emit(store)
      builder.ret(nil)

      CopyPropagationPass.new(function).run.should be > 0

      rewritten = function.get_block(function.entry_block).instructions
        .find { |instruction| instruction.is_a?(Store) }.not_nil!.as(Store)
      rewritten.ptr.should eq(pointer)
      rewritten.field_type.should eq(TypeRef::INT64)
    end
  end
end
