require "../spec_helper"
require "../../src/compiler/bootstrap_shims"
require "../../src/compiler/hir/hir"
require "../../src/compiler/hir/escape_analysis"
require "../../src/compiler/hir/taint_analysis"
require "../../src/compiler/hir/memory_strategy"
require "../../src/compiler/mir/mir"
require "../../src/compiler/mir/hir_to_mir"

describe "HIR function body presence contract" do
  it "distinguishes a registered bodyless function from emitted body evidence" do
    mod = Adamas::HIR::Module.new
    bodyless = mod.create_function("bodyless", Adamas::HIR::TypeRef::VOID)
    with_instruction = mod.create_function("with_instruction", Adamas::HIR::TypeRef::INT32)
    with_return = mod.create_function("with_return", Adamas::HIR::TypeRef::VOID)
    explicit_unreachable = mod.create_function("explicit_unreachable", Adamas::HIR::TypeRef::VOID)

    mod.has_function?("bodyless").should be_true
    bodyless.get_block(bodyless.entry_block).terminator.should be_a(Adamas::HIR::Unreachable)
    mod.has_function_with_body?("bodyless").should be_false

    with_instruction.get_block(with_instruction.entry_block).add(
      Adamas::HIR::Literal.new(with_instruction.next_value_id, Adamas::HIR::TypeRef::INT32, 1_i64)
    )
    mod.has_function_with_body?("with_instruction").should be_true

    with_return.get_block(with_return.entry_block).terminator = Adamas::HIR::Return.new
    mod.has_function_with_body?("with_return").should be_true

    explicit_unreachable.get_block(explicit_unreachable.entry_block).terminator = Adamas::HIR::Unreachable.new
    mod.has_function_with_body?("explicit_unreachable").should be_true
  end

  it "preserves bodyless HIR functions as MIR unreachable stubs" do
    hir_mod = Adamas::HIR::Module.new("test")
    hir_mod.create_function("bodyless", Adamas::HIR::TypeRef::VOID)
    live = hir_mod.create_function("live", Adamas::HIR::TypeRef::VOID)
    live.get_block(live.entry_block).terminator = Adamas::HIR::Return.new

    hir_mod.has_function?("bodyless").should be_true
    hir_mod.has_function_with_body?("bodyless").should be_false
    hir_mod.has_function_with_body?("live").should be_true

    mir_mod = hir_mod.lower_to_mir
    bodyless_mir = mir_mod.functions.find { |func| func.name == "bodyless" }
    live_mir = mir_mod.functions.find { |func| func.name == "live" }

    bodyless_mir.should_not be_nil
    live_mir.should_not be_nil
    bodyless_entry = bodyless_mir.not_nil!.get_block(bodyless_mir.not_nil!.entry_block)
    live_entry = live_mir.not_nil!.get_block(live_mir.not_nil!.entry_block)

    bodyless_entry.instructions.should be_empty
    bodyless_entry.terminator.should be_a(Adamas::MIR::Unreachable)
    live_entry.terminator.should be_a(Adamas::MIR::Return)
  end
end
