require "../spec_helper"
require "../../src/compiler/hir/hir"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/hir/escape_analysis"
require "../../src/compiler/hir/taint_analysis"
require "../../src/compiler/hir/memory_strategy"
require "../../src/compiler/mir/mir"
require "../../src/compiler/mir/hir_to_mir"

describe Adamas::MIR::HIRToMIRLowering do
  describe "cross-block phi pre-scan" do
    it "keeps owned reference results alive until a phi consumes them" do
      hir_mod = Adamas::HIR::Module.new("phi_cross_block_arc")
      box_ref = hir_mod.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Class,
        "OwnedBox"
      ))

      producer = hir_mod.create_function("make_box", box_ref)
      producer_block = producer.get_block(producer.entry_block)
      allocation = Adamas::HIR::Allocate.new(producer.next_value_id, box_ref)
      allocation.lifetime = Adamas::HIR::LifetimeTag::HeapEscape
      producer_block.add(allocation)
      producer_block.terminator = Adamas::HIR::Return.new(allocation.id)

      caller = hir_mod.create_function("select_box", box_ref)
      entry_block = caller.get_block(caller.entry_block)
      then_block_id = caller.create_block(0_u32)
      else_block_id = caller.create_block(0_u32)
      merge_block_id = caller.create_block(0_u32)

      condition = Adamas::HIR::Literal.new(
        caller.next_value_id,
        Adamas::HIR::TypeRef::BOOL,
        true
      )
      entry_block.add(condition)
      entry_block.terminator = Adamas::HIR::Branch.new(
        condition.id,
        then_block_id,
        else_block_id
      )

      then_block = caller.get_block(then_block_id)
      then_call = Adamas::HIR::Call.without_receiver(
        caller.next_value_id,
        box_ref,
        "make_box",
        [] of Adamas::HIR::ValueId
      )
      then_block.add(then_call)
      unconsumed_call = Adamas::HIR::Call.without_receiver(
        caller.next_value_id,
        box_ref,
        "make_box",
        [] of Adamas::HIR::ValueId
      )
      then_block.add(unconsumed_call)
      then_block.terminator = Adamas::HIR::Jump.new(merge_block_id)

      else_block = caller.get_block(else_block_id)
      else_call = Adamas::HIR::Call.without_receiver(
        caller.next_value_id,
        box_ref,
        "make_box",
        [] of Adamas::HIR::ValueId
      )
      else_block.add(else_call)
      else_block.terminator = Adamas::HIR::Jump.new(merge_block_id)

      merge_block = caller.get_block(merge_block_id)
      phi = Adamas::HIR::Phi.new(caller.next_value_id, box_ref)
      phi.add_incoming(then_block_id, then_call.id)
      phi.add_incoming(else_block_id, else_call.id)
      merge_block.add(phi)
      merge_block.terminator = Adamas::HIR::Return.new(phi.id)

      empty_ivars = [] of Adamas::HIR::IVarInfo
      empty_class_vars = [] of Adamas::HIR::ClassVarInfo
      class_infos = {
        "OwnedBox" => Adamas::HIR::ClassInfo.new(
          "OwnedBox",
          box_ref,
          empty_ivars,
          empty_class_vars,
          8
        ),
      } of String => Adamas::HIR::ClassInfo
      lowering = Adamas::MIR::HIRToMIRLowering.new(hir_mod)
      lowering.register_class_types(class_infos)
      mir_mod = lowering.lower
      mir_caller = mir_mod.functions.find { |function| function.name == caller.name }.not_nil!
      mir_phi = mir_caller.blocks
        .flat_map(&.instructions)
        .find(&.is_a?(Adamas::MIR::Phi))
        .not_nil!
        .as(Adamas::MIR::Phi)

      mir_phi.incoming.size.should eq(2)
      phi_source_with_unconsumed_call : Adamas::MIR::BasicBlock? = nil
      mir_phi.incoming.each do |(_, incoming_id)|
        source_block = mir_caller.blocks.find do |block|
          block.instructions.any? { |instruction| instruction.id == incoming_id }
        end
        source_block.should_not be_nil
        source_block.not_nil!.instructions.any? do |instruction|
          instruction.is_a?(Adamas::MIR::Call) && instruction.id == incoming_id
        end.should be_true
        source_block.not_nil!.instructions.any? do |instruction|
          instruction.is_a?(Adamas::MIR::RCDecrement) && instruction.ptr == incoming_id
        end.should be_false
        if source_block.not_nil!.instructions.count(&.is_a?(Adamas::MIR::Call)) == 2
          phi_source_with_unconsumed_call = source_block
        end
      end

      phi_source_with_unconsumed_call.should_not be_nil
      source_calls = phi_source_with_unconsumed_call.not_nil!.instructions
        .select(&.is_a?(Adamas::MIR::Call))
        .map(&.as(Adamas::MIR::Call))
      source_calls.size.should eq(2)
      unconsumed_mir_call = source_calls.find do |call|
        mir_phi.incoming.none? { |(_, incoming_id)| incoming_id == call.id }
      end
      unconsumed_mir_call.should_not be_nil
      phi_source_with_unconsumed_call.not_nil!.instructions.any? do |instruction|
        instruction.is_a?(Adamas::MIR::RCDecrement) &&
          instruction.ptr == unconsumed_mir_call.not_nil!.id
      end.should be_true
    end
  end
end
