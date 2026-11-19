require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_queue_projection(*, close_cycle : Bool = true, need_result : Bool = true, change_source : Bool = false)
    consumer = "RecFactory.consumer"
    producer = "RecFactory.value"
    source = __test_projection_source(producer)
    source = __test_projection_source("RecFactory.reference") if change_source
    pending = ExactResultPending.new(consumer, producer, source, producer_requires_result: need_result)
    selected = ForceLowerSuspendedRequest.new(pending, __test_projection_replay(consumer), false)
    dep = close_cycle ? consumer : "RecFactory.inferred"
    @force_lower_provisional_dependencies[consumer] = Set{producer}
    @force_lower_provisional_dependencies[producer] = Set{dep}
    @force_lower_retry_work << selected
    @force_lower_retry_work << ForceLowerRetryRequest.new(producer, [dep], false,
      __test_projection_replay(producer), __test_projection_source(producer), true)
    force_lower_retry_waits_for_queued_producer?(selected).should be_true if close_cycle && !change_source
    index = open_recursive_struct_result
    if index
      index.should eq(0)
      settled_force_lower_result?(producer).should be_false
      @force_lower_provisional_dependencies[consumer].should eq(Set{producer})
      recursive_struct_result_available?(selected).should be_true
      force_lower_retry_waits_for_queued_producer?(selected).should be_false
      @module.function_by_name(producer).not_nil!.source_return_result_receipt = nil
      recursive_struct_result_available?(selected).should be_false
      force_lower_retry_waits_for_queued_producer?(selected).should be_true
    end
    !index.nil?
  end

  def __test_retry_checked_self_result(
    change : Symbol, method : String = "recursive_value", dependency : String = "value",
  ) : Bool
    name = __test_projection_method_name(method)
    producer = __test_projection_method_name(dependency)
    settled_force_lower_result?(producer).should be_true
    original = @module.function_by_name(name).not_nil!
    source = __test_projection_source(name)
    callsite = __test_ordinary_projection_callsite
    replay = __test_projection_replay(name, callsite)
    @pending_arg_types[name] = callsite
    dependencies = change == :only_self ? [name] : [name, producer]
    @force_lower_provisional_dependencies[name] = dependencies.to_set
    if change == :missing_receipt
      original.source_return_result_receipt = nil
    elsif change == :unsettled_producer
      @force_lower_provisional_dependencies[producer] = Set{name}
    elsif change == :unknown_argument_kind
      replay = __test_projection_replay(name, CallsiteArgs.new([TypeRef::BOOL], nil, nil))
    elsif change == :changed_result_kind
      original.source_return_value_facts = original.source_return_value_facts.not_nil!.map { |(type, _)| {type, true} }
    elsif change == :replaced_return
      block = original.blocks.find { |candidate| candidate.terminator.is_a?(Return) }.not_nil!
      block.terminator = Return.new(block.terminator.as(Return).value)
    end

    request = ForceLowerRetryRequest.new(name, dependencies, false, replay, source, true)
    result = with_force_lower_exact_source(name, source) { retry_force_lower_depth_request(request) }
    if result
      @module.function_by_name(name).not_nil!.same?(original).should be_false
      settled_force_lower_result?(name).should be_true
    else
      @module.function_by_name(name).not_nil!.same?(original).should be_true
      @force_lower_provisional_dependencies[name].should eq(dependencies.to_set)
    end
    result
  end

  def __test_advance_projected_consumer(change : Symbol) : Bool
    consumer = "RecFactory.consumer"
    first = "RecFactory.value"
    second = "RecFactory.reference"
    replay = __test_projection_replay(consumer)
    previous = ForceLowerSuspendedRequest.new(
      ExactResultPending.new(consumer, first, __test_projection_source(first)), replay, false,
    )
    @force_lower_provisional_dependencies[consumer] = Set{first}
    @force_lower_provisional_dependencies[first] = Set{consumer}
    enqueue_force_lower_retry_work(previous)
    first_work = ForceLowerRetryRequest.new(first, [consumer], false, __test_projection_replay(first),
      __test_projection_source(first), true)
    enqueue_force_lower_retry_work(first_work)
    @force_lower_retry_driver_active = true
    open_recursive_struct_result.should eq(0)
    recursive_struct_result_available?(previous).should be_true
    @force_lower_retry_work.delete_at(0)

    # The replay consumed the checked projection before finding another wait.
    @force_lower_provisional_dependencies[consumer] = Set{second}
    @force_lower_provisional_dependencies[second] = Set{first}
    second_work = ForceLowerRetryRequest.new(second, [first], false, __test_projection_replay(second),
      __test_projection_source(second), true)
    enqueue_force_lower_retry_work(second_work)
    pending = ExactResultPending.new(consumer, second, __test_projection_source(second))
    capture = ForceLowerReplayCapture.new(consumer, nil)
    capture.binding = replay
    pending.consumer_capture = capture

    case change
    when :unowned
      @force_lower_retry_work.delete_at(0)
    when :invalidated
      @module.function_by_name(first).not_nil!.source_return_result_receipt = nil
    end

    return false unless advance_suspended_consumer(previous, pending)
    has_equivalent_queued_force_lower_work?(previous).should be_true
    has_queued_force_lower_edge_continuation?(consumer, second).should be_true
    queued_exact_force_lower_demand?(first, previous.pending.producer_source).should be_true
    force_lower_retry_waits_for_queued_producer?(previous).should be_true
    settled_force_lower_result?(first).should be_false
    queued = @force_lower_retry_work.dup
    advance_suspended_consumer(previous, pending).should be_false
    @force_lower_retry_work.should eq(queued)
    expect_raises(ExactResultPending) { validate_recursive_struct_results }
    true
  ensure
    @force_lower_retry_driver_active = false
  end

  private def __test_nested_projection_pending(change : Symbol)
    producer = "RecFactory.value"
    middle = "RecFactory.reference"
    leaf = "RecFactory.inferred"
    producer_replay = __test_projection_replay(producer)
    middle_replay = __test_projection_replay(middle)
    leaf_source = __test_projection_source(change == :foreign_leaf ? "RecFactory.object_type" : leaf)
    inner = ExactResultPending.new(middle, leaf, leaf_source,
      producer_requires_result: change != :body_leaf)
    middle_capture = ForceLowerReplayCapture.new(middle, nil)
    middle_capture.binding = change == :foreign_relay ? producer_replay : middle_replay
    inner.consumer_capture = middle_capture
    outer = ExactResultPending.new(producer, middle, __test_projection_source(middle),
      middle_replay, producer_pending: inner)
    producer_capture = ForceLowerReplayCapture.new(producer, nil)
    producer_capture.binding = producer_replay
    outer.consumer_capture = producer_capture
    if change == :pending_leaf
      @force_lower_provisional_dependencies[leaf] = Set{producer}
    elsif change == :pending_middle
      @force_lower_provisional_dependencies[middle] = Set{producer}
    end
    ExactResultPending.new("RecFactory.consumer", producer, __test_projection_source(producer),
      producer_replay, producer_requires_result: change != :outer_body_only, producer_pending: outer)
  end

  def __test_nested_published_projection(change : Symbol) : String?
    pending = __test_nested_projection_pending(change)
    if change == :missing_return
      @module.function_by_name(pending.producer).not_nil!.source_return_result_receipt = nil
    end
    exact_final_struct_result(pending).try { |type| get_type_name_from_ref(type) }
  end

  private def __test_projection_source(name : String)
    ForceLowerExactSourceBinding.new(@function_defs[name], @function_def_arenas[name], name)
  end

  private def __test_projection_replay(name : String, callsite : CallsiteArgs? = nil)
    source = __test_projection_source(name)
    call = callsite || CallsiteArgs.new([] of TypeRef, nil, nil, selected_target: name)
    ForceLowerReplayCallsite.new(source.source_def, source.source_arena, call,
      @type_param_map.dup, @current_namespace_override, name, exact_source_binding: source)
  end

  def __test_projection_fact(method : String, stale : Bool = false) : String?
    name = "RecFactory.#{method}"
    definition = @function_defs[name]
    arena = @function_def_arenas[name]
    source = ForceLowerExactSourceBinding.new(definition, arena, name)
    pending = ExactResultPending.new("RecFactory.consumer", name, source, producer_requires_result: true)
    function = @module.function_by_name(name) || raise "missing function #{name}"
    @force_lower_provisional_dependencies[name] = Set{"RecFactory.consumer"}
    function.source_return_result_receipt = nil if stale
    exact_final_struct_result(pending).try { |type| get_type_name_from_ref(type) }
  end

  def __test_projection_input_admitted?(literal : Bool = false, sibling_source : Bool = false) : Bool
    producer, _consumer, _request, ctx, producer_source, _consumer_source = __test_open_projection_use
    source = sibling_source ? __test_projection_source(__test_projection_method_name("sibling_value")) : producer_source
    value = Literal.new(ctx.next_id, TypeRef::BOOL, false)
    ctx.emit(value)
    ctx.mark_type_literal(value.id) if literal
    facts = call_resolution_source_argument_facts(ctx, [value.id], [TypeRef::BOOL])
    result = @module.function_by_name(producer).not_nil!.return_type
    recursive_struct_result_at_source_call?(ctx, producer, result, [TypeRef::BOOL], facts, nil,
      source.source_def, source.source_def, source.source_arena, producer)
  end

  def __test_projection_emission_current?(
    literal : Bool = false,
    wrong_target : Bool = false,
    wrong_result : Bool = false,
    replace_call : Bool = false,
    replace_argument : Bool = false,
    change_argument_kind : Bool = false,
    change_producer_block_slot : Bool = false,
  ) : Bool
    producer, consumer, _request, ctx, producer_source, _consumer_source = __test_open_projection_use
    value = Literal.new(ctx.next_id, TypeRef::BOOL, false)
    ctx.emit(value)
    ctx.mark_type_literal(value.id) if literal
    facts = call_resolution_source_argument_facts(ctx, [value.id], [TypeRef::BOOL])
    result = @module.function_by_name(producer).not_nil!.return_type
    admitted = recursive_struct_result_at_source_call?(ctx, producer, result, [TypeRef::BOOL], facts, nil,
      producer_source.source_def, producer_source.source_def, producer_source.source_arena, producer)
    return false unless admitted

    use = @deferred_struct_result_uses[{consumer, producer}].not_nil!
    ticket = use.begin_emission_ticket(ctx.function)
    emitted_target = wrong_target ? __test_projection_method_name("sibling_value") : producer
    emitted_result = wrong_result ? TypeRef::INT32 : result
    call = Call.new(ctx.next_id, emitted_result, "")
    call.configure_without_receiver(emitted_target, [value.id])
    ctx.emit(call)
    ctx.register_source_value_facts(call.id, [{emitted_result, false}])
    witness = recursive_struct_result_emission_witness(ctx, producer, call, [TypeRef::BOOL], nil)
    return false unless witness
    return false unless use.discharge_emission_ticket(ticket, witness)
    use.discharge_emission_ticket(ticket, witness).should be_false

    if replace_call
      replacement = Call.new(call.id, emitted_result, "")
      replacement.configure_without_receiver(emitted_target, [value.id])
      block = ctx.function.get_block(ctx.current_block_id)
      index = block.instructions.index! { |instruction| instruction.same?(call) }
      block.replace(index, replacement)
    end
    if replace_argument
      replacement = Literal.new(value.id, TypeRef::BOOL, false)
      block = ctx.function.get_block(ctx.current_block_id)
      index = block.instructions.index! { |instruction| instruction.same?(value) }
      block.replace(index, replacement)
    end
    ctx.mark_type_literal(value.id) if change_argument_kind
    if change_producer_block_slot
      target = @module.function_by_name(producer).not_nil!
      parameter = target.params.last
      target.set_block_param_type(parameter.id, parameter.type)
    end
    recursive_struct_result_emission_witness_current?(use, witness)
  end

  def __test_projection_two_emission_tickets?(omit_second : Bool = false) : Bool
    producer, consumer, _request, ctx, _producer_source, _consumer_source = __test_open_projection_use
    use = @deferred_struct_result_uses[{consumer, producer}].not_nil!
    2.times do |index|
      ticket = use.begin_emission_ticket(ctx.function)
      next if omit_second && index == 1

      value = Literal.new(ctx.next_id, TypeRef::BOOL, false)
      ctx.emit(value)
      call = Call.new(ctx.next_id, @module.function_by_name(producer).not_nil!.return_type, "")
      call.configure_without_receiver(producer, [value.id])
      ctx.emit(call)
      ctx.register_source_value_facts(call.id, [{call.type, false}])
      witness = recursive_struct_result_emission_witness(ctx, producer, call, [TypeRef::BOOL], nil) || return false
      return false unless use.discharge_emission_ticket(ticket, witness)
    end
    use.emission_obligations_complete?
  end

  def __test_projection_ticket_reset? : Bool
    producer, consumer, _request, ctx, _producer_source, _consumer_source = __test_open_projection_use
    use = @deferred_struct_result_uses[{consumer, producer}].not_nil!
    obsolete_ticket = use.begin_emission_ticket(ctx.function)
    use.retire_function_body(ctx.function)
    current_ticket = use.begin_emission_ticket(ctx.function)
    value = Literal.new(ctx.next_id, TypeRef::BOOL, false)
    ctx.emit(value)
    call = Call.new(ctx.next_id, @module.function_by_name(producer).not_nil!.return_type, "")
    call.configure_without_receiver(producer, [value.id])
    ctx.emit(call)
    ctx.register_source_value_facts(call.id, [{call.type, false}])
    witness = recursive_struct_result_emission_witness(ctx, producer, call, [TypeRef::BOOL], nil) || return false
    use.discharge_emission_ticket(obsolete_ticket, witness).should be_false
    use.discharge_emission_ticket(current_ticket, witness) && use.emission_obligations_complete?
  end

  def __test_retired_physical_ticket_rejects_replacement? : Bool
    producer, consumer, _request, old_ctx, _producer_source, _consumer_source = __test_open_projection_use
    use = @deferred_struct_result_uses[{consumer, producer}].not_nil!
    old_function = old_ctx.function
    old_ticket = use.begin_emission_ticket(old_function)
    foreign_ticket = use.begin_emission_ticket(old_function)

    old_value = Literal.new(old_ctx.next_id, TypeRef::BOOL, false)
    old_ctx.emit(old_value)
    old_call = Call.new(old_ctx.next_id, use.expected, "")
    old_call.configure_without_receiver(producer, [old_value.id])
    old_ctx.emit(old_call)
    old_ctx.register_source_value_facts(old_call.id, [{use.expected, false}])
    old_witness = recursive_struct_result_emission_witness(old_ctx, producer, old_call, [TypeRef::BOOL], nil) || return false

    foreign = Function.new(old_function.id + 1_u32, consumer, old_function.return_type)
    old_function.params.each do |parameter|
      foreign.add_param(parameter.name, parameter.type, parameter.is_block)
    end
    foreign_ctx = LoweringContext.new(foreign, @module, @arena)
    foreign_ctx.source_result_replay_consumer = consumer
    foreign_value_id = foreign_ctx.next_id
    while foreign_value_id < old_value.id
      foreign_value_id = foreign_ctx.next_id
    end
    return false unless foreign_value_id == old_value.id
    foreign_value = Literal.new(foreign_value_id, TypeRef::BOOL, false)
    foreign_ctx.emit(foreign_value)
    foreign_call = Call.new(foreign_ctx.next_id, use.expected, "")
    foreign_call.configure_without_receiver(producer, [foreign_value.id])
    foreign_ctx.emit(foreign_call)
    foreign_ctx.register_source_value_facts(foreign_call.id, [{use.expected, false}])
    foreign_witness = recursive_struct_result_emission_witness(foreign_ctx, producer, foreign_call, [TypeRef::BOOL], nil) || return false

    old_function.same?(foreign).should be_false
    old_call.id.should eq(foreign_call.id)
    old_value.id.should eq(foreign_value.id)
    old_witness.function.same?(old_function).should be_true
    foreign_witness.function.same?(foreign).should be_true
    use.discharge_emission_ticket(foreign_ticket, foreign_witness).should be_false
    use.discharge_emission_ticket(old_ticket, old_witness).should be_true

    return false unless remove_hir_function(consumer)
    use.emissions.empty?.should be_true
    replacement = @module.create_function(consumer, old_function.return_type)
    old_function.params.each do |parameter|
      replacement.add_param(parameter.name, parameter.type, parameter.is_block)
    end
    new_ctx = LoweringContext.new(replacement, @module, @arena)
    new_ctx.source_result_replay_consumer = consumer
    new_value_id = new_ctx.next_id
    while new_value_id < old_value.id
      new_value_id = new_ctx.next_id
    end
    return false unless new_value_id == old_value.id
    new_value = Literal.new(new_value_id, TypeRef::BOOL, false)
    new_ctx.emit(new_value)
    new_call = Call.new(new_ctx.next_id, use.expected, "")
    new_call.configure_without_receiver(producer, [new_value.id])
    new_ctx.emit(new_call)
    new_ctx.register_source_value_facts(new_call.id, [{use.expected, false}])
    new_witness = recursive_struct_result_emission_witness(new_ctx, producer, new_call, [TypeRef::BOOL], nil) || return false

    old_function.same?(replacement).should be_false
    old_call.id.should eq(new_call.id)
    old_value.id.should eq(new_value.id)
    new_witness.function.same?(replacement).should be_true
    use.discharge_emission_ticket(old_ticket, new_witness).should be_false

    new_ticket = use.begin_emission_ticket(replacement)
    return false unless use.discharge_emission_ticket(new_ticket, new_witness)
    use.emission_obligations_complete? && recursive_struct_result_emission_witness_current?(use, new_witness)
  end

  def __test_unrelated_retirement_preserves_physical_ticket? : Bool
    producer, consumer, _request, ctx, _producer_source, _consumer_source = __test_open_projection_use
    use = @deferred_struct_result_uses[{consumer, producer}].not_nil!
    ticket = use.begin_emission_ticket(ctx.function)
    unrelated_name = "RecFactory.unrelated_retirement_probe"
    unrelated = @module.create_function(unrelated_name, TypeRef::VOID)
    return false unless remove_hir_function(unrelated_name)
    return false unless use.emissions.size == 1

    value = Literal.new(ctx.next_id, TypeRef::BOOL, false)
    ctx.emit(value)
    call = Call.new(ctx.next_id, use.expected, "")
    call.configure_without_receiver(producer, [value.id])
    ctx.emit(call)
    ctx.register_source_value_facts(call.id, [{use.expected, false}])
    witness = recursive_struct_result_emission_witness(ctx, producer, call, [TypeRef::BOOL], nil) || return false
    unrelated.same?(ctx.function).should be_false
    use.discharge_emission_ticket(ticket, witness) && use.emission_obligations_complete?
  end

  def __test_instance_projection_emission_current?(
    replace_receiver : Bool = false,
    change_receiver_kind : Bool = false,
  ) : Bool
    producer, consumer, _request, ctx, _producer_source, _consumer_source = __test_open_projection_use("RecClass")
    self_param = ctx.function.params.first? || return false
    return false unless self_param.name == "self"
    ctx.register_type(self_param.id, self_param.type)
    receiver = Copy.new(ctx.next_id, self_param.type, self_param.id)
    ctx.emit(receiver)
    value = Literal.new(ctx.next_id, TypeRef::BOOL, false)
    ctx.emit(value)
    result = @module.function_by_name(producer).not_nil!.return_type
    use = @deferred_struct_result_uses[{consumer, producer}].not_nil!
    ticket = use.begin_emission_ticket(ctx.function)
    call = Call.with_receiver(ctx.next_id, result, receiver.id, producer, [value.id])
    call.args.should eq([value.id])
    call.args.includes?(receiver.id).should be_false
    ctx.emit(call)
    ctx.register_source_value_facts(call.id, [{result, false}])
    witness = recursive_struct_result_emission_witness(ctx, producer, call, [TypeRef::BOOL], receiver.id) || return false
    return false unless use.discharge_emission_ticket(ticket, witness)

    if replace_receiver
      replacement = Copy.new(receiver.id, self_param.type, self_param.id)
      block = ctx.function.get_block(ctx.current_block_id)
      index = block.instructions.index! { |instruction| instruction.same?(receiver) }
      block.replace(index, replacement)
    end
    ctx.mark_type_literal(receiver.id) if change_receiver_kind
    recursive_struct_result_emission_witness_current?(use, witness)
  end

  def __test_nilary_projection_emission? : Bool
    producer, consumer, _request, ctx, _producer_source, _consumer_source = __test_open_projection_use(nilary: true)
    result = @module.function_by_name(producer).not_nil!.return_type
    use = @deferred_struct_result_uses[{consumer, producer}]
    call = Call.without_receiver(ctx.next_id, result, producer, [] of ValueId)
    ctx.emit(call)
    ctx.register_source_value_facts(call.id, [{result, false}])
    witness = recursive_struct_result_emission_witness(ctx, producer, call, [] of TypeRef, nil) || return false
    recursive_struct_result_emission_witness_current?(use, witness)
  end

  def __test_nilary_projection_accepts_extra_fact? : Bool
    callsite = CallsiteArgs.new([] of TypeRef, nil, nil)
    facts = [SourceCallArgument.new(TypeRef::BOOL, false).as(SourceCallArgument?)]
    recursive_struct_result_argument_facts_match?(callsite, [] of TypeRef, facts)
  end

  def __test_queued_struct_input?(change : Symbol) : Bool
    name = __test_projection_method_name("value_for")
    source = __test_projection_source(name)
    replay = __test_projection_replay(name, __test_projection_bool_callsite(name, false))
    @force_lower_retry_work.clear
    unless change == :missing
      @force_lower_retry_work << ForceLowerRetryRequest.new(name, [] of String, false, replay, source, true)
    end
    if change == :conflicting_argument
      first_class = __test_projection_replay(name, __test_projection_bool_callsite(name, true))
      @force_lower_retry_work << ForceLowerRetryRequest.new(name, [] of String, false, first_class, source, true)
    end
    if change == :entry_namespace
      return with_namespace_override_or_clear("RecClass") { !live_force_lower_callsite_for(name, source).nil? }
    end
    if change == :source
      source = __test_projection_source(__test_projection_method_name("sibling_value"))
    end
    !live_force_lower_callsite_for(name, source).nil?
  end

  def __test_ordinary_queued_owner_recovery?(change : Symbol = :unchanged) : Bool
    name = __test_projection_method_name("value_for")
    source = __test_projection_source(name)
    callsite = __test_ordinary_projection_callsite
    replay = ForceLowerReplayCallsite.new(
      source.source_def,
      source.source_arena,
      callsite,
      @type_param_map.dup,
      @current_namespace_override,
      source.source_registry_name,
      exact_source_binding: source,
    )
    @force_lower_retry_work.clear
    @force_lower_retry_work << ForceLowerRetryRequest.new(name, [] of String, false, replay, source, true)

    case change
    when :registered_definition
      original = @function_defs[name]
      replacement = @function_defs.values.find { |candidate| !candidate.same?(original) } || return false
      @function_defs[name] = replacement
      begin
        return live_force_lower_callsite_for(name, source).nil?
      ensure
        @function_defs[name] = original
      end
    when :registered_arena
      original = @function_def_arenas[name]
      replacement = Adamas::Compiler::Frontend::AstArena.new
      @function_def_arenas[name] = replacement
      begin
        return live_force_lower_callsite_for(name, source).nil?
      ensure
        @function_def_arenas[name] = original
      end
    when :entry_namespace
      return with_namespace_override_or_clear("RecClass") do
        live_force_lower_callsite_for(name, source).nil?
      end
    when :entry_type_param_map
      prior = @type_param_map.dup
      @type_param_map.clear
      @type_param_map["OwnerProbe"] = "RecToken"
      begin
        return live_force_lower_callsite_for(name, source).nil?
      ensure
        @type_param_map.clear
        prior.each { |key, value| @type_param_map[key] = value }
      end
    else
      live_force_lower_callsite_for(name, source).try do |retained|
        same_force_lower_replay_callsite?(retained, replay)
      end || false
    end
  ensure
    @force_lower_retry_work.clear
  end

  def __test_ordinary_recovery_callsite_kinds : Tuple(Bool, Bool, Bool, Bool)
    name = __test_projection_method_name("value_for")
    source = __test_projection_source(name)
    type = TypeRef::BOOL
    instance_fact = SourceCallArgument.new(type, false)
    class_fact = SourceCallArgument.new(type, true)
    instance = CallsiteArgs.new(
      [type], [false], nil,
      source_argument_facts: [instance_fact.as(SourceCallArgument?)],
    )
    class_object = CallsiteArgs.new(
      [type], [true], nil,
      source_argument_facts: [class_fact.as(SourceCallArgument?)],
    )
    unknown_kind = CallsiteArgs.new([type], nil, nil)
    callback = CallsiteArgs.new(
      [type], [false], nil, has_block: true,
      source_argument_facts: [instance_fact.as(SourceCallArgument?)],
    )
    {
      ordinary_recursive_source_callsite?(name, source, instance),
      ordinary_recursive_source_callsite?(name, source, class_object),
      ordinary_recursive_source_callsite?(name, source, unknown_kind),
      ordinary_recursive_source_callsite?(name, source, callback),
    }
  end

  def __test_recursive_producer_callsite_consensus(change : Symbol = :unchanged) : Bool
    name = __test_projection_method_name("value_for")
    source = __test_projection_source(name)
    flags = change == :absent_kind ? nil : [false]
    plain = CallsiteArgs.new([TypeRef::BOOL], flags, nil)
    kind = change == :class_object
    evidence_type = change == :other_type ? TypeRef::INT32 : TypeRef::BOOL
    fact = SourceCallArgument.new(evidence_type, kind)
    rich = CallsiteArgs.new([TypeRef::BOOL], [kind], nil,
      source_argument_facts: [fact.as(SourceCallArgument?)])
    first = __test_projection_replay(name, plain)
    second = if change == :other_namespace
               with_namespace_override_or_clear("RecClass") { __test_projection_replay(name, rich) }
             else
               __test_projection_replay(name, rich)
             end
    first, second = second, first if change == :reverse
    pending = ExactResultPending.new("RecFactory.consumer", name, source, first)
    @force_lower_retry_work.clear
    @force_lower_retry_work << ForceLowerRetryRequest.new(name, [] of String, false, second, source, true)
    chosen = recursive_struct_result_producer_replay(pending)
    if change == :unchanged || change == :reverse
      chosen.try(&.callsite.source_argument_facts) == rich.source_argument_facts
    else
      chosen.nil?
    end
  ensure
    @force_lower_retry_work.clear
  end

  def __test_suspended_constant_return?(change : Symbol, *, nested : Bool = false) : Bool
    name = "RecFactory.value"
    source = __test_projection_source(name)
    replay = __test_projection_replay(name)
    original = @module.function_by_name(name).not_nil!
    type = original.return_type
    partial = Function.new(original.id, name, type)
    ctx = LoweringContext.new(partial, @module, source.source_arena)
    block = ctx.get_block(ctx.current_block_id)
    if change == :unreachable
      ctx.switch_to_block(ctx.create_block)
      block = ctx.get_block(ctx.current_block_id)
    end
    read = ClassVarGet.new(ctx.next_id, type, "RecFactory", "BASE")
    ctx.emit(read)
    facts = [{type, false}]
    ctx.register_source_value_facts(read.id, facts)
    @constant_types["RecFactory::BASE"] = type
    @constant_source_value_facts["RecFactory::BASE"] = facts
    returned = Return.new(read.id)
    ctx.terminate(returned)
    body = ForceLowerActiveBody.new(partial, source.source_def, source.source_arena,
      [] of TypeRef, [] of String, type)
    anchor = PartialStructReturn.new(replay, ctx, block, returned, read, body)
    pending = nested ? __test_nested_projection_pending(change) : ExactResultPending.new("RecFactory.consumer", name, source)

    case change
    when :replaced_read
      block.replace(0, ClassVarGet.new(read.id, type, read.class_name, read.var_name))
    when :replaced_return
      ctx.terminate(Return.new(read.id))
    when :missing_constant
      @constant_types.delete("RecFactory::BASE")
    when :changed_kind
      @constant_source_value_facts["RecFactory::BASE"] = [{type, true}]
    when :changed_operand
      ctx.register_source_value_facts(read.id, [{type, true}])
    when :changed_replay_source
      other = __test_projection_replay("RecFactory.reference")
      anchor = PartialStructReturn.new(other, ctx, block, returned, read, body)
    end
    !checked_partial_struct_result(pending, anchor).nil?
  end

  def __test_suspended_checked_call_return?(change : Symbol) : Bool
    name = "RecFactory.value"
    producer = __test_projection_method_name("value_for")
    source = __test_projection_source(name)
    replay = __test_projection_replay(name)
    original = @module.function_by_name(name).not_nil!
    type = original.return_type
    partial = Function.new(original.id, name, type)
    ctx = LoweringContext.new(partial, @module, source.source_arena)
    ctx.switch_to_block(ctx.create_block) if change == :unreachable
    block = ctx.get_block(ctx.current_block_id)

    operand = Literal.new(ctx.next_id, TypeRef::BOOL, false)
    ctx.emit(operand)
    other = Literal.new(ctx.next_id, TypeRef::BOOL, true)
    ctx.emit(other)
    call = Call.new(ctx.next_id, type, "")
    call.configure_without_receiver(producer, [operand.id], change == :virtual)
    ctx.emit(call)
    ctx.register_source_value_facts(call.id, [{type, false}])
    returned = Return.new(call.id)
    ctx.terminate(returned)
    result = suspended_return_call_result(ctx, call) || return false
    body = ForceLowerActiveBody.new(partial, source.source_def, source.source_arena,
      [] of TypeRef, [] of String, type)
    anchor = PartialStructReturn.new(replay, ctx, block, returned, call, body, result)

    case change
    when :different_operand
      call.configure_without_receiver(producer, [other.id])
    when :replaced_operand
      block.replace(0, Literal.new(operand.id, TypeRef::BOOL, false))
    when :stale_receipt
      @module.function_by_name(producer).not_nil!.source_return_result_receipt = nil
    when :provisional
      @force_lower_provisional_dependencies[producer] = Set{"RecFactory.consumer"}
    when :changed_kind
      ctx.register_source_value_facts(call.id, [{type, true}])
    when :different_target
      call.configure_without_receiver(__test_projection_method_name("sibling_value"), [operand.id])
    end
    pending = ExactResultPending.new("RecFactory.consumer", name, source)
    !checked_partial_struct_result(pending, anchor).nil?
  end

  def __test_suspended_return_with_default?(change : Symbol) : Bool
    name = __test_projection_method_name("value_with_default")
    source = __test_projection_source(name)
    original = @module.function_by_name(name).not_nil!
    remove_hir_function(name).should be_true
    function = @module.create_function(name, original.return_type)
    function.add_param("flag", TypeRef::BOOL)
    function.set_param_default_literal(0, "false")
    callsite = case change
               when :missing_argument
                 CallsiteArgs.new([] of TypeRef, nil, nil)
               when :different_type
                 CallsiteArgs.new([TypeRef::INT32], [false], nil)
               when :unknown_kind
                 CallsiteArgs.new([TypeRef::BOOL], nil, nil)
               when :class_object
                 CallsiteArgs.new([TypeRef::BOOL], [true], nil)
               when :named_argument
                 CallsiteArgs.new([TypeRef::BOOL], [false], nil, has_named_args: true)
               else
                 __test_ordinary_projection_callsite
               end
    capture = ForceLowerReplayCapture.new(name, nil)
    capture.binding = __test_projection_replay(name, callsite)
    @force_lower_active_replay_captures[name] = capture
    set_function_state(name, FunctionLoweringState::InProgress)
    retain_active_force_lower_body(function, source.source_def, source.source_arena)
    active_force_lower_body_owns_callsite?(name, callsite).should be_false

    ctx = LoweringContext.new(function, @module, source.source_arena)
    type = function.return_type
    read = ClassVarGet.new(ctx.next_id, type, "RecFactory", "BASE")
    ctx.emit(read)
    facts = [{type, false}]
    ctx.register_source_value_facts(read.id, facts)
    @constant_types["RecFactory::BASE"] = type
    @constant_source_value_facts["RecFactory::BASE"] = facts
    ctx.terminate(Return.new(read.id)) unless change == :missing_return
    anchor = suspended_struct_return(ctx) || return false

    function.set_param_default_literal(0, "true") if change == :changed_default
    pending = ExactResultPending.new("RecFactory.consumer", name, source)
    !checked_partial_struct_result(pending, anchor).nil?
  end

  private def __test_open_projection_use(owner : String = "RecFactory", *, nilary : Bool = false)
    producer = nilary ? "RecFactory.value" : __test_projection_method_name("value_for", owner)
    consumer = nilary ? "RecFactory.consumer" : __test_projection_method_name("consumer_for", owner)
    producer_source = __test_projection_source(producer)
    consumer_source = __test_projection_source(consumer)
    producer_callsite = nilary ? nil : __test_projection_bool_callsite(producer, false)
    consumer_callsite = nilary ? nil : __test_projection_bool_callsite(consumer, false)
    producer_replay = __test_projection_replay(producer, producer_callsite)
    consumer_replay = __test_projection_replay(consumer, consumer_callsite)
    pending = ExactResultPending.new(consumer, producer, producer_source)
    request = ForceLowerSuspendedRequest.new(pending, consumer_replay, false)
    @force_lower_provisional_dependencies[consumer] = Set{producer}
    @force_lower_provisional_dependencies[producer] = Set{consumer}
    @force_lower_retry_work << request
    @force_lower_retry_work << ForceLowerRetryRequest.new(producer, [consumer], false,
      producer_replay, producer_source, true)
    candidate = recursive_struct_result_producer_replay(pending) || raise "missing current test producer replay"
    result_type = exact_final_struct_result(pending) || raise "missing final test producer result"
    recursive_struct_result_callsite_argument_facts(candidate.callsite) || raise "missing test producer input kind facts"
    @deferred_struct_result_uses[{consumer, producer}] = DeferredStructResultUse.new(request, result_type, candidate)
    @force_lower_replay_source_bindings[consumer] = consumer_source
    function = @module.function_by_name(consumer).not_nil!
    ctx = LoweringContext.new(function, @module, @arena)
    ctx.source_result_replay_consumer = consumer
    {producer, consumer, request, ctx, producer_source, consumer_source}
  end

  private def __test_projection_method_name(method : String, owner : String = "RecFactory") : String
    prefix = owner == "RecFactory" ? "#{owner}.#{method}" : "#{owner}##{method}"
    @module.functions.find do |function|
      function.name.starts_with?(prefix) && @module.has_function_with_body?(function.name)
    end.try(&.name) || raise "missing materialized projection test method #{method}"
  end

  private def __test_projection_bool_callsite(name : String, literal : Bool) : CallsiteArgs
    fact = SourceCallArgument.new(TypeRef::BOOL, literal)
    CallsiteArgs.new([TypeRef::BOOL], [literal], nil, selected_target: name,
      source_argument_facts: [fact.as(SourceCallArgument?)])
  end

  private def __test_ordinary_projection_callsite : CallsiteArgs
    fact = SourceCallArgument.new(TypeRef::BOOL, false)
    CallsiteArgs.new([TypeRef::BOOL], [false], nil,
      source_argument_facts: [fact.as(SourceCallArgument?)])
  end
end

private def recursive_projection_converter
  source = <<-CRYSTAL
    struct RecToken
    end

    class RecClass
      def value_for(flag : Bool) : RecToken
        RecToken.new
      end

      def consumer_for(flag : Bool)
        value_for(flag)
      end
    end

    module RecFactory
      def self.value : RecToken
        RecToken.new
      end

      def self.value_for(flag : Bool) : RecToken
        if flag
          RecToken.new
        else
          RecToken.new
        end
      end

      def self.sibling_value(flag : Bool) : RecToken
        if flag
          RecToken.new
        else
          RecToken.new
        end
      end

      def self.recursive_value(flag : Bool) : RecToken
        return recursive_value(false) if flag
        value
      end

      def self.recursive_reference(flag : Bool) : RecClass?
        return recursive_reference(false) if flag
        return nil unless gate(flag)
        reference
      end

      def self.gate(flag : Bool) : Bool
        !flag
      end

      def self.recursive_tagged(flag : Bool) : Int32?
        return recursive_tagged(false) if flag
        return nil unless gate(flag)
        42
      end

      def self.value_with_default(flag : Bool = false) : RecToken
        RecToken.new
      end

      def self.consumer
        value
      end

      def self.consumer_for(flag : Bool)
        value_for(flag)
      end

      def self.reference : RecClass
        RecClass.new
      end

      def self.object_type : RecToken.class
        RecToken
      end

      def self.inferred
        RecToken.new
      end
    end

    RecFactory.value
    RecFactory.consumer
    RecFactory.reference
    RecFactory.object_type
    RecFactory.inferred
    RecClass.new.consumer_for(false)
    RecFactory.value_for(false)
    RecFactory.value_with_default(false)
    RecFactory.recursive_value(true)
    RecFactory.recursive_reference(true)
    RecFactory.recursive_tagged(true)
    RecFactory.sibling_value(false)
    RecFactory.consumer_for(false)
    CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "/tmp/recursive_result_projection_spec.cr"})
  converter.no_prelude = true
  main = [] of UInt64
  program.roots.each do |id|
    case node = arena[id]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    else
      main << id.index.to_u64
    end
  end
  converter.lower_main(main)
  converter.flush_pending_functions
  converter
end

describe "source result projection inside a recursive specialization" do
  it "admits the published instance of an explicitly declared final struct" do
    recursive_projection_converter.__test_projection_fact("value").should eq("RecToken")
  end

  it "opens a result-only edge of a live cycle while keeping its body obligations" do
    recursive_projection_converter.__test_queue_projection.should be_true
    recursive_projection_converter.__test_queue_projection(close_cycle: false).should be_false
    recursive_projection_converter.__test_queue_projection(need_result: false).should be_false
    recursive_projection_converter.__test_queue_projection(change_source: true).should be_false
  end

  it "rebuilds a completed recursive body after its independent producer settles" do
    recursive_projection_converter.__test_retry_checked_self_result(:current).should be_true
  end

  it "rebuilds a completed recursive nullable reference result after its producer settles" do
    recursive_projection_converter.__test_retry_checked_self_result(
      :current, "recursive_reference", "gate",
    ).should be_true
  end

  it "retains the wait for a nullable result without independent current evidence" do
    [:missing_receipt, :unsettled_producer, :unknown_argument_kind, :only_self, :changed_result_kind, :replaced_return].each do |change|
      recursive_projection_converter.__test_retry_checked_self_result(
        change, "recursive_reference", "gate",
      ).should be_false
    end
    recursive_projection_converter.__test_retry_checked_self_result(
      :current, "recursive_tagged", "gate",
    ).should be_false
  end

  it "retains a recursive wait without current result and argument evidence" do
    [:missing_receipt, :unsettled_producer, :unknown_argument_kind].each do |change|
      recursive_projection_converter.__test_retry_checked_self_result(change).should be_false
    end
  end

  it "keeps both continuations after a checked projection exposes a new pending result" do
    recursive_projection_converter.__test_advance_projected_consumer(:current).should be_true
    recursive_projection_converter.__test_advance_projected_consumer(:unowned).should be_false
    recursive_projection_converter.__test_advance_projected_consumer(:invalidated).should be_false
  end

  it "consumes a published result only after each relayed source demand is current and settled" do
    recursive_projection_converter.__test_nested_published_projection(:valid).should eq("RecToken")
    recursive_projection_converter.__test_nested_published_projection(:body_leaf).should eq("RecToken")
    [:pending_leaf, :pending_middle, :foreign_relay, :foreign_leaf, :missing_return, :outer_body_only].each do |change|
      recursive_projection_converter.__test_nested_published_projection(change).should be_nil
    end
  end

  it "checks every descendant before reusing a suspended physical return" do
    recursive_projection_converter.__test_suspended_constant_return?(:valid, nested: true).should be_true
    recursive_projection_converter.__test_suspended_constant_return?(:body_leaf, nested: true).should be_true
    [:pending_leaf, :pending_middle, :foreign_relay, :foreign_leaf, :replaced_return, :outer_body_only].each do |change|
      recursive_projection_converter.__test_suspended_constant_return?(change, nested: true).should be_false
    end
  end

  it "requires both the exact body receipt and a final instance restriction" do
    converter = recursive_projection_converter
    converter.__test_projection_fact("value", stale: true).should be_nil
    converter.__test_projection_fact("reference").should be_nil
    converter.__test_projection_fact("object_type").should be_nil
    converter.__test_projection_fact("inferred").should be_nil
  end

  it "binds the projected argument to the queued producer's value kind and source" do
    converter = recursive_projection_converter
    converter.__test_projection_input_admitted?.should be_true
    converter.__test_projection_input_admitted?(literal: true).should be_false
    converter.__test_projection_input_admitted?(sibling_source: true).should be_false
  end

  it "requires the same direct call object, target, and instance result at HIR emission" do
    converter = recursive_projection_converter
    converter.__test_projection_emission_current?.should be_true
    converter.__test_projection_emission_current?(literal: true).should be_false
    converter.__test_projection_emission_current?(wrong_target: true).should be_false
    converter.__test_projection_emission_current?(wrong_result: true).should be_false
    converter.__test_projection_emission_current?(replace_call: true).should be_false
    converter.__test_projection_emission_current?(replace_argument: true).should be_false
    converter.__test_projection_emission_current?(change_argument_kind: true).should be_false
  end

  it "rejects a producer rebuilt with a block slot where the call supplies an ordinary argument" do
    recursive_projection_converter.__test_projection_emission_current?(change_producer_block_slot: true).should be_false
  end

  it "rechecks the live instance receiver definition and kind at emission" do
    converter = recursive_projection_converter
    converter.__test_instance_projection_emission_current?.should be_true
    converter.__test_instance_projection_emission_current?(replace_receiver: true).should be_false
    converter.__test_instance_projection_emission_current?(change_receiver_kind: true).should be_false
  end

  it "requires agreement on the source, stored argument kinds and entry environment of a queued replay" do
    converter = recursive_projection_converter
    converter.__test_queued_struct_input?(:unchanged).should be_true
    [:missing, :conflicting_argument, :source, :entry_namespace].each do |change|
      converter.__test_queued_struct_input?(change).should be_false
    end
  end

  it "restores ordinary queued work only for the same live owner and entry context" do
    converter = recursive_projection_converter
    converter.__test_ordinary_queued_owner_recovery?.should be_true
    [:registered_definition, :registered_arena, :entry_namespace, :entry_type_param_map].each do |change|
      converter.__test_ordinary_queued_owner_recovery?(change).should be_true
    end
  end

  it "admits a nonempty instance recipe but rejects a class object, unknown kind, or callback" do
    instance, class_object, unknown_kind, callback = recursive_projection_converter.__test_ordinary_recovery_callsite_kinds
    instance.should be_true
    class_object.should be_false
    unknown_kind.should be_false
    callback.should be_false
  end

  it "keeps the richer equivalent instance recipe and rejects missing or crossed evidence" do
    converter = recursive_projection_converter
    [:unchanged, :reverse, :absent_kind, :class_object, :other_type, :other_namespace].each do |change|
      converter.__test_recursive_producer_callsite_consensus(change).should be_true
    end
  end

  it "permits a provisional struct result only while its reachable source return and operand are current" do
    converter = recursive_projection_converter
    converter.__test_suspended_constant_return?(:unchanged).should be_true
    [:replaced_read, :replaced_return, :unreachable, :missing_constant, :changed_kind,
     :changed_operand, :changed_replay_source].each do |change|
      converter.__test_suspended_constant_return?(change).should be_false
    end
  end

  it "keeps a direct call result only with its active checked body and exact emitted operands" do
    recursive_projection_converter.__test_suspended_checked_call_return?(:unchanged).should be_true
    [:different_operand, :replaced_operand, :stale_receipt, :provisional, :unreachable,
     :changed_kind, :different_target, :virtual].each do |change|
      recursive_projection_converter.__test_suspended_checked_call_return?(change).should be_false
    end
  end

  it "keeps a checked return after the exact body has bound every default-capable parameter" do
    recursive_projection_converter.__test_suspended_return_with_default?(:unchanged).should be_true
    [:missing_argument, :different_type, :unknown_kind, :class_object,
     :named_argument, :missing_return, :changed_default].each do |change|
      recursive_projection_converter.__test_suspended_return_with_default?(change).should be_false
    end
  end

  it "recognizes the recorded argument evidence of a real zero-argument call" do
    recursive_projection_converter.__test_nilary_projection_emission?.should be_true
  end

  it "rejects an argument fact supplied to a zero-argument projection" do
    recursive_projection_converter.__test_nilary_projection_accepts_extra_fact?.should be_false
  end

  it "requires one emitted HIR call for every admitted invocation" do
    converter = recursive_projection_converter
    converter.__test_projection_two_emission_tickets?.should be_true
    converter.__test_projection_two_emission_tickets?(omit_second: true).should be_false
  end

  it "retires tickets with an obsolete consumer body" do
    recursive_projection_converter.__test_projection_ticket_reset?.should be_true
  end

  it "rejects a delayed ticket from a retired same-named physical consumer" do
    recursive_projection_converter.__test_retired_physical_ticket_rejects_replacement?.should be_true
  end

  it "preserves a ticket when an unrelated physical function is retired" do
    recursive_projection_converter.__test_unrelated_retirement_preserves_physical_ticket?.should be_true
  end
end
