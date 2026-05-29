require "../spec_helper"
require "../../src/compiler/hir/hir"
require "../../src/compiler/mir/mir"
require "../../src/compiler/mir/hir_to_mir"

describe Adamas::MIR::HIRToMIRLowering do
  describe "debug locations" do
    it "preserves index_set source locations on the lowered array_set instruction" do
      hir_mod = Adamas::HIR::Module.new("test")
      hir_func = hir_mod.create_function("index_set_debug", Adamas::HIR::TypeRef::VOID)
      arr = hir_func.add_param("arr", Adamas::HIR::TypeRef::POINTER)
      idx = hir_func.add_param("idx", Adamas::HIR::TypeRef::INT32)
      value = hir_func.add_param("value", Adamas::HIR::TypeRef::INT32)
      block = hir_func.get_block(hir_func.entry_block)

      index_set = Adamas::HIR::IndexSet.new(
        hir_func.next_value_id,
        Adamas::HIR::TypeRef::INT32,
        arr.id,
        idx.id,
        value.id
      )
      block.add(index_set)
      block.terminator = Adamas::HIR::Return.new
      hir_func.record_value_location(index_set.id, Adamas::HIR::SourceLocation.new("debug_index_set.cr", 11, 3))

      mir_mod = hir_mod.lower_to_mir
      mir_func = mir_mod.functions.find { |f| f.name == "index_set_debug" }
      mir_func.should_not be_nil

      array_set = mir_func.not_nil!.blocks
        .flat_map(&.instructions)
        .find { |inst| inst.is_a?(Adamas::MIR::ArraySet) }
      array_set.should_not be_nil

      location = mir_func.not_nil!.value_location(array_set.not_nil!.id)
      location.should_not be_nil
      location.not_nil!.file.should eq("debug_index_set.cr")
      location.not_nil!.line.should eq(11)
      location.not_nil!.column.should eq(3)
    end

    it "keeps the original source location when transparent copy lowering reuses a MIR value" do
      hir_mod = Adamas::HIR::Module.new("test")
      hir_func = hir_mod.create_function("copy_debug", Adamas::HIR::TypeRef::INT32)
      block = hir_func.get_block(hir_func.entry_block)

      literal = Adamas::HIR::Literal.new(hir_func.next_value_id, Adamas::HIR::TypeRef::INT32, 42_i64)
      copy_a = Adamas::HIR::Copy.new(hir_func.next_value_id, Adamas::HIR::TypeRef::INT32, literal.id)
      copy_b = Adamas::HIR::Copy.new(hir_func.next_value_id, Adamas::HIR::TypeRef::INT32, copy_a.id)

      block.add(literal)
      block.add(copy_a)
      block.add(copy_b)
      block.terminator = Adamas::HIR::Return.new(copy_b.id)

      hir_func.record_value_location(literal.id, Adamas::HIR::SourceLocation.new("copy_debug.cr", 10, 6))
      hir_func.record_value_location(copy_a.id, Adamas::HIR::SourceLocation.new("copy_debug.cr", 10, 3))
      hir_func.record_value_location(copy_b.id, Adamas::HIR::SourceLocation.new("copy_debug.cr", 11, 8))

      mir_mod = hir_mod.lower_to_mir
      mir_func = mir_mod.functions.find { |f| f.name == "copy_debug" }
      mir_func.should_not be_nil

      constant = mir_func.not_nil!.blocks
        .flat_map(&.instructions)
        .find { |inst| inst.is_a?(Adamas::MIR::Constant) }
      constant.should_not be_nil

      location = mir_func.not_nil!.value_location(constant.not_nil!.id)
      location.should_not be_nil
      location.not_nil!.file.should eq("copy_debug.cr")
      location.not_nil!.line.should eq(10)
      location.not_nil!.column.should eq(6)
    end
  end
end
