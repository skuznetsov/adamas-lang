require "spec"
require "../../src/compiler/bootstrap_shims"
require "../../src/compiler/mir/hir_to_mir"

class Adamas::MIR::HIRToMIRLowering
  def __test_owned_return_names : Array(String)
    build_owned_return_set
    @owned_return_funcs.to_a
  end
end

OWNED_RETURN_BOX_REF = Adamas::HIR::TypeRef.new(900_u32)

private def add_owned_return_heap_alloc(function : Adamas::HIR::Function) : Adamas::HIR::Allocate
  alloc = Adamas::HIR::Allocate.new(function.next_value_id, OWNED_RETURN_BOX_REF)
  alloc.lifetime = Adamas::HIR::LifetimeTag::HeapEscape
  function.get_block(function.entry_block).add(alloc)
  alloc
end

private def owned_return_names(hir_mod : Adamas::HIR::Module) : Array(String)
  Adamas::MIR::HIRToMIRLowering.new(hir_mod).__test_owned_return_names.sort
end

describe "owned return provenance" do
  it "accepts a direct heap allocation as owned" do
    hir_mod = Adamas::HIR::Module.new("owned_direct")
    function = hir_mod.create_function("make_box", OWNED_RETURN_BOX_REF)
    alloc = add_owned_return_heap_alloc(function)
    function.get_block(function.entry_block).terminator = Adamas::HIR::Return.new(alloc.id)

    owned_return_names(hir_mod).should eq(["make_box"])
  end

  it "accepts a transitive call to a proven owned producer" do
    hir_mod = Adamas::HIR::Module.new("owned_transitive")
    producer = hir_mod.create_function("make_box", OWNED_RETURN_BOX_REF)
    alloc = add_owned_return_heap_alloc(producer)
    producer.get_block(producer.entry_block).terminator = Adamas::HIR::Return.new(alloc.id)

    wrapper = hir_mod.create_function("forward_box", OWNED_RETURN_BOX_REF)
    call = Adamas::HIR::Call.without_receiver(
      wrapper.next_value_id,
      OWNED_RETURN_BOX_REF,
      "make_box",
      [] of Adamas::HIR::ValueId
    )
    wrapper.get_block(wrapper.entry_block).add(call)
    wrapper.get_block(wrapper.entry_block).terminator = Adamas::HIR::Return.new(call.id)

    owned_return_names(hir_mod).should eq(["forward_box", "make_box"])
  end

  it "rejects a Phi that can return a borrowed parameter" do
    hir_mod = Adamas::HIR::Module.new("mixed_phi_parameter")
    function = hir_mod.create_function("evaluate_to_macro_value", OWNED_RETURN_BOX_REF)
    parameter = function.add_param("borrowed", OWNED_RETURN_BOX_REF)

    then_block_id = function.create_block(0_u32)
    else_block_id = function.create_block(0_u32)
    merge_block_id = function.create_block(0_u32)

    entry = function.get_block(function.entry_block)
    condition = Adamas::HIR::Literal.new(function.next_value_id, Adamas::HIR::TypeRef::BOOL, true)
    entry.add(condition)
    entry.terminator = Adamas::HIR::Branch.new(condition.id, then_block_id, else_block_id)

    then_block = function.get_block(then_block_id)
    alloc = Adamas::HIR::Allocate.new(function.next_value_id, OWNED_RETURN_BOX_REF)
    alloc.lifetime = Adamas::HIR::LifetimeTag::HeapEscape
    then_block.add(alloc)
    then_block.terminator = Adamas::HIR::Jump.new(merge_block_id)

    else_block = function.get_block(else_block_id)
    else_block.terminator = Adamas::HIR::Jump.new(merge_block_id)

    merge_block = function.get_block(merge_block_id)
    phi = Adamas::HIR::Phi.new(function.next_value_id, OWNED_RETURN_BOX_REF)
    phi.add_incoming(then_block_id, alloc.id)
    # Parameters are not instructions in the function map. This is the
    # unknown/borrowed origin that the current any-Allocate test drops.
    phi.add_incoming(else_block_id, parameter.id)
    merge_block.add(phi)
    merge_block.terminator = Adamas::HIR::Return.new(phi.id)

    owned_return_names(hir_mod).should_not contain("evaluate_to_macro_value")
  end

  it "rejects mixed direct returns across control-flow blocks" do
    hir_mod = Adamas::HIR::Module.new("mixed_direct_returns")
    function = hir_mod.create_function("mixed_direct_returns", OWNED_RETURN_BOX_REF)
    parameter = function.add_param("borrowed", OWNED_RETURN_BOX_REF)

    then_block_id = function.create_block(0_u32)
    else_block_id = function.create_block(0_u32)
    entry = function.get_block(function.entry_block)
    condition = Adamas::HIR::Literal.new(function.next_value_id, Adamas::HIR::TypeRef::BOOL, true)
    entry.add(condition)
    entry.terminator = Adamas::HIR::Branch.new(condition.id, then_block_id, else_block_id)

    then_block = function.get_block(then_block_id)
    then_alloc = Adamas::HIR::Allocate.new(function.next_value_id, OWNED_RETURN_BOX_REF)
    then_alloc.lifetime = Adamas::HIR::LifetimeTag::HeapEscape
    then_block.add(then_alloc)
    then_block.terminator = Adamas::HIR::Return.new(then_alloc.id)

    else_block = function.get_block(else_block_id)
    else_block.terminator = Adamas::HIR::Return.new(parameter.id)

    owned_return_names(hir_mod).should_not contain("mixed_direct_returns")
  end

  it "rejects a parameter passed through Copy, Cast, and Phi" do
    hir_mod = Adamas::HIR::Module.new("mixed_copy_cast_phi")
    function = hir_mod.create_function("mixed_copy_cast_phi", OWNED_RETURN_BOX_REF)
    parameter = function.add_param("borrowed", OWNED_RETURN_BOX_REF)

    then_block_id = function.create_block(0_u32)
    else_block_id = function.create_block(0_u32)
    merge_block_id = function.create_block(0_u32)
    entry = function.get_block(function.entry_block)
    condition = Adamas::HIR::Literal.new(function.next_value_id, Adamas::HIR::TypeRef::BOOL, true)
    entry.add(condition)
    entry.terminator = Adamas::HIR::Branch.new(condition.id, then_block_id, else_block_id)

    then_block = function.get_block(then_block_id)
    then_alloc = Adamas::HIR::Allocate.new(function.next_value_id, OWNED_RETURN_BOX_REF)
    then_alloc.lifetime = Adamas::HIR::LifetimeTag::HeapEscape
    then_block.add(then_alloc)
    then_block.terminator = Adamas::HIR::Jump.new(merge_block_id)

    else_block = function.get_block(else_block_id)
    copy = Adamas::HIR::Copy.new(function.next_value_id, OWNED_RETURN_BOX_REF, parameter.id)
    else_block.add(copy)
    cast = Adamas::HIR::Cast.new(function.next_value_id, OWNED_RETURN_BOX_REF, copy.id, OWNED_RETURN_BOX_REF)
    else_block.add(cast)
    else_block.terminator = Adamas::HIR::Jump.new(merge_block_id)

    merge_block = function.get_block(merge_block_id)
    phi = Adamas::HIR::Phi.new(function.next_value_id, OWNED_RETURN_BOX_REF)
    phi.add_incoming(then_block_id, then_alloc.id)
    phi.add_incoming(else_block_id, cast.id)
    merge_block.add(phi)
    merge_block.terminator = Adamas::HIR::Return.new(phi.id)

    owned_return_names(hir_mod).should_not contain("mixed_copy_cast_phi")
  end

  it "rejects an unknown call passed through Phi with an allocation" do
    hir_mod = Adamas::HIR::Module.new("mixed_unknown_call_phi")
    function = hir_mod.create_function("mixed_unknown_call_phi", OWNED_RETURN_BOX_REF)

    then_block_id = function.create_block(0_u32)
    else_block_id = function.create_block(0_u32)
    merge_block_id = function.create_block(0_u32)
    entry = function.get_block(function.entry_block)
    condition = Adamas::HIR::Literal.new(function.next_value_id, Adamas::HIR::TypeRef::BOOL, true)
    entry.add(condition)
    entry.terminator = Adamas::HIR::Branch.new(condition.id, then_block_id, else_block_id)

    then_block = function.get_block(then_block_id)
    then_alloc = Adamas::HIR::Allocate.new(function.next_value_id, OWNED_RETURN_BOX_REF)
    then_alloc.lifetime = Adamas::HIR::LifetimeTag::HeapEscape
    then_block.add(then_alloc)
    then_block.terminator = Adamas::HIR::Jump.new(merge_block_id)

    else_block = function.get_block(else_block_id)
    unknown_call = Adamas::HIR::Call.without_receiver(
      function.next_value_id,
      OWNED_RETURN_BOX_REF,
      "unknown_provider",
      [] of Adamas::HIR::ValueId
    )
    else_block.add(unknown_call)
    else_block.terminator = Adamas::HIR::Jump.new(merge_block_id)

    merge_block = function.get_block(merge_block_id)
    phi = Adamas::HIR::Phi.new(function.next_value_id, OWNED_RETURN_BOX_REF)
    phi.add_incoming(then_block_id, then_alloc.id)
    phi.add_incoming(else_block_id, unknown_call.id)
    merge_block.add(phi)
    merge_block.terminator = Adamas::HIR::Return.new(phi.id)

    owned_return_names(hir_mod).should_not contain("mixed_unknown_call_phi")
  end

  it "accepts a Phi whose every origin is a proven allocation" do
    hir_mod = Adamas::HIR::Module.new("all_owned_phi")
    function = hir_mod.create_function("make_box", OWNED_RETURN_BOX_REF)
    then_block_id = function.create_block(0_u32)
    else_block_id = function.create_block(0_u32)
    merge_block_id = function.create_block(0_u32)
    entry = function.get_block(function.entry_block)
    condition = Adamas::HIR::Literal.new(function.next_value_id, Adamas::HIR::TypeRef::BOOL, true)
    entry.add(condition)
    entry.terminator = Adamas::HIR::Branch.new(condition.id, then_block_id, else_block_id)

    then_block = function.get_block(then_block_id)
    then_alloc = Adamas::HIR::Allocate.new(function.next_value_id, OWNED_RETURN_BOX_REF)
    then_alloc.lifetime = Adamas::HIR::LifetimeTag::HeapEscape
    then_block.add(then_alloc)
    then_block.terminator = Adamas::HIR::Jump.new(merge_block_id)

    else_block = function.get_block(else_block_id)
    else_alloc = Adamas::HIR::Allocate.new(function.next_value_id, OWNED_RETURN_BOX_REF)
    else_alloc.lifetime = Adamas::HIR::LifetimeTag::HeapEscape
    else_block.add(else_alloc)
    else_block.terminator = Adamas::HIR::Jump.new(merge_block_id)

    merge_block = function.get_block(merge_block_id)
    phi = Adamas::HIR::Phi.new(function.next_value_id, OWNED_RETURN_BOX_REF)
    phi.add_incoming(then_block_id, then_alloc.id)
    phi.add_incoming(else_block_id, else_alloc.id)
    merge_block.add(phi)
    merge_block.terminator = Adamas::HIR::Return.new(phi.id)

    owned_return_names(hir_mod).should contain("make_box")
  end
end

private OWNED_RETURN_CONSUMER_REF = Adamas::HIR::TypeRef::STRING

private def add_owned_consumer_alloc(function : Adamas::HIR::Function) : Adamas::HIR::Allocate
  alloc = Adamas::HIR::Allocate.new(function.next_value_id, OWNED_RETURN_CONSUMER_REF)
  alloc.lifetime = Adamas::HIR::LifetimeTag::HeapEscape
  function.get_block(function.entry_block).add(alloc)
  alloc
end

private def make_owned_consumer_module : Adamas::HIR::Module
  hir_mod = Adamas::HIR::Module.new("consumer_ownership")

  factory = hir_mod.create_function("pure_factory", OWNED_RETURN_CONSUMER_REF)
  factory_alloc = add_owned_consumer_alloc(factory)
  factory.get_block(factory.entry_block).terminator = Adamas::HIR::Return.new(factory_alloc.id)

  mixed = hir_mod.create_function("mixed_factory", OWNED_RETURN_CONSUMER_REF)
  borrowed = mixed.add_param("borrowed", OWNED_RETURN_CONSUMER_REF)
  then_id = mixed.create_block(0_u32)
  else_id = mixed.create_block(0_u32)
  entry = mixed.get_block(mixed.entry_block)
  condition = Adamas::HIR::Literal.new(mixed.next_value_id, Adamas::HIR::TypeRef::BOOL, true)
  entry.add(condition)
  entry.terminator = Adamas::HIR::Branch.new(condition.id, then_id, else_id)
  then_block = mixed.get_block(then_id)
  then_alloc = Adamas::HIR::Allocate.new(mixed.next_value_id, OWNED_RETURN_CONSUMER_REF)
  then_alloc.lifetime = Adamas::HIR::LifetimeTag::HeapEscape
  then_block.add(then_alloc)
  then_block.terminator = Adamas::HIR::Return.new(then_alloc.id)
  else_block = mixed.get_block(else_id)
  else_block.terminator = Adamas::HIR::Return.new(borrowed.id)

  mixed_consumer = hir_mod.create_function("consume_mixed", Adamas::HIR::TypeRef::VOID)
  mixed_arg = mixed_consumer.add_param("arg", OWNED_RETURN_CONSUMER_REF)
  mixed_call = Adamas::HIR::Call.without_receiver(
    mixed_consumer.next_value_id,
    OWNED_RETURN_CONSUMER_REF,
    "mixed_factory",
    [mixed_arg.id]
  )
  mixed_consumer.get_block(mixed_consumer.entry_block).add(mixed_call)
  mixed_consumer.get_block(mixed_consumer.entry_block).terminator = Adamas::HIR::Return.new

  pure_consumer = hir_mod.create_function("consume_pure", Adamas::HIR::TypeRef::VOID)
  pure_call = Adamas::HIR::Call.without_receiver(
    pure_consumer.next_value_id,
    OWNED_RETURN_CONSUMER_REF,
    "pure_factory",
    [] of Adamas::HIR::ValueId
  )
  pure_consumer.get_block(pure_consumer.entry_block).add(pure_call)
  pure_consumer.get_block(pure_consumer.entry_block).terminator = Adamas::HIR::Return.new

  hir_mod
end

private def owned_consumer_mir_function(mir : Adamas::MIR::Module, name : String) : Adamas::MIR::Function
  mir.functions.each do |function|
    return function if function.name == name
  end
  raise "missing MIR function #{name}"
end

private def count_owned_consumer_rc_dec(function : Adamas::MIR::Function) : Int32
  count = 0
  function.blocks.each do |block|
    block.instructions.each do |instruction|
      count += 1 if instruction.is_a?(Adamas::MIR::RCDecrement)
    end
  end
  count
end

describe "owned return consumer cleanup" do
  it "omits mixed callee cleanup while retaining pure factory cleanup" do
    lowering = Adamas::MIR::HIRToMIRLowering.new(make_owned_consumer_module)
    mir = lowering.lower
    count_owned_consumer_rc_dec(owned_consumer_mir_function(mir, "consume_mixed")).should eq(0)
    count_owned_consumer_rc_dec(owned_consumer_mir_function(mir, "consume_pure")).should eq(1)
  end
end
