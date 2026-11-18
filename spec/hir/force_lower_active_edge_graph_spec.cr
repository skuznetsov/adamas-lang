require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_materialize_active_edge_function(name : String) : Nil
    lower_function_if_needed(name)
    @function_defs.has_key?(name).should be_true
    @function_def_arenas.has_key?(name).should be_true
  end

  def __test_blocked_retry_drains_independent_sibling : Nil
    blocked = "edge_pending_child"
    consumer = "edge_pending_parent"
    sibling = "edge_pending_sibling"
    leaf = "edge_leaf"
    @module.has_function_with_body?(sibling).should be_false
    settled_force_lower_result?(leaf).should be_true

    root = ExactResultPending.new(consumer, blocked, __test_exact_source(blocked))
    other = ExactResultPending.new(sibling, leaf, __test_exact_source(leaf))
    enqueue_force_lower_retry_work(ForceLowerSuspendedRequest.new(other, __test_replay_callsite(sibling), false))
    set_function_state(blocked, FunctionLoweringState::InProgress)
    begin
      begin
        result = run_force_lower_retry_driver(ForceLowerSuspendedRequest.new(root, __test_replay_callsite(consumer), false))
        result.should be_false
      rescue pending : ExactResultPending
        pending.should be(root)
      end
      settled_force_lower_result?(sibling).should be_true
      settled_force_lower_result?(consumer).should be_false
      settled_force_lower_result?(blocked).should be_false
    ensure
      clear_function_state(blocked)
    end
  end

  def __test_start_active_edge_graph : Nil
    @force_lower_retry_work.clear
    @force_lower_result_suspensions.clear
    @force_lower_retry_driver_active = true
  end

  def __test_stop_active_edge_graph : Nil
    @force_lower_retry_driver_active = false
    @force_lower_retry_work.clear
    @force_lower_result_suspensions.clear
  end

  def __test_start_nested_pending_capture(
    parent_name : String,
    child_name : String,
  ) : {ForceLowerReplayCapture, ForceLowerReplayCapture, ForceLowerReplayCallsite}
    parent_source = __test_exact_source(parent_name)
    parent = ForceLowerReplayCapture.new(parent_name, nil)
    parent.source = parent_source
    parent.binding = __test_replay_callsite(parent_name)
    @force_lower_current_replay_capture = parent
    @force_lower_active_replay_captures[parent_name] = parent
    child, replay = __test_add_nested_pending_child(parent, child_name)
    {parent, child, replay}
  end

  def __test_add_nested_pending_child(
    parent : ForceLowerReplayCapture,
    child_name : String,
  ) : {ForceLowerReplayCapture, ForceLowerReplayCallsite}
    child = ForceLowerReplayCapture.new(child_name, parent)
    child.source = __test_exact_source(child_name)
    child.binding = __test_replay_callsite(child_name)
    {child, child.binding.not_nil!}
  end

  def __test_nested_pending(child : ForceLowerReplayCapture) : ExactResultPending
    producer = "edge_leaf"
    pending = ExactResultPending.new(
      child.name,
      producer,
      __test_exact_source(producer),
      __test_replay_callsite(producer),
      producer_requires_result: false,
      producer_bypass_inline_yield: true,
    )
    pending.consumer_capture = child
    pending
  end

  def __test_retry_nested_pending(
    pending : ExactResultPending,
    replay : ForceLowerReplayCallsite,
  ) : Bool
    retry_suspended_exact_result(pending, replay, 0, false)
  rescue blocked : ExactResultPending
    false
  end

  def __test_provisional_dependency_names(name : String) : Array(String)
    (@force_lower_provisional_dependencies[name]? || Set(String).new).to_a.sort
  end

  def __test_relay_preserves_nested_pending?(
    parent : ForceLowerReplayCapture,
    pending : ExactResultPending,
  ) : Bool
    relayed = relay_suspended_exact_result(parent.name, parent, pending)
    return false unless relayed && (child = pending.consumer_capture)
    relayed.consumer == parent.name && relayed.producer == pending.consumer &&
      relayed.producer_pending.try(&.same?(pending)) == true &&
      relayed.producer_replay.try { |replay| same_force_lower_replay_callsite?(replay, child.binding) } == true &&
      same_force_lower_exact_source_binding?(relayed.producer_source, child.source.not_nil!)
  end

  def __test_replace_active_nested_parent(parent : ForceLowerReplayCapture) : Nil
    replacement = ForceLowerReplayCapture.new(parent.name, nil)
    replacement.source = __test_exact_source(parent.name)
    replacement.binding = __test_replay_callsite(parent.name)
    @force_lower_current_replay_capture = replacement
    @force_lower_active_replay_captures[parent.name] = replacement
  end

  def __test_retry_with_stale_nested_parent_source(
    parent_name : String,
    pending : ExactResultPending,
    replay : ForceLowerReplayCallsite,
  ) : Bool
    original = @function_defs[parent_name]? || raise "missing parent Def for #{parent_name}"
    stale, _ = __test_foreign_source_pair(parent_name)
    @function_defs[parent_name] = stale
    begin
      __test_retry_nested_pending(pending, replay)
    ensure
      @function_defs[parent_name] = original
    end
  end

  def __test_stop_nested_pending_capture(parent_name : String) : Nil
    __test_stop_active_edge_graph
    @force_lower_provisional_dependencies.delete(parent_name)
    @force_lower_current_replay_capture = nil
    @force_lower_active_replay_captures.delete(parent_name)
  end

  def __test_exact_source(name : String) : ForceLowerExactSourceBinding
    source_def = @function_defs[name]? || raise "missing registered Def for #{name}"
    source_arena = @function_def_arenas[name]? || raise "missing registered arena for #{name}"
    ForceLowerExactSourceBinding.new(source_def, source_arena, name)
  end

  def __test_replay_callsite(name : String) : ForceLowerReplayCallsite
    source = __test_exact_source(name)
    callsite = CallsiteArgs.new(
      [] of TypeRef,
      nil,
      nil,
      false,
      false,
      nil,
      name,
    )
    ForceLowerReplayCallsite.new(
      source.source_def,
      source.source_arena,
      callsite,
      @type_param_map.dup,
      @current_namespace_override,
      name,
      nil,
      nil,
      source,
    )
  end

  def __test_nilary_callsite_kind_evidence : Nil
    types = [] of TypeRef
    absent = CallsiteArgs.new(types, nil, nil)
    explicit = CallsiteArgs.new(types, [] of Bool, nil)
    pending_callsite_compatible_with_replay?(absent, explicit).should be_true
    pending_callsite_compatible_with_replay?(explicit, absent).should be_true
    ordinary_active_body_callsite?(absent).should be_true

    remember_callsite_arg_types("edge_leaf", types, [] of Bool)
    remember_callsite_arg_types("edge_leaf", types, nil)
    bucket = @pending_arg_types_by_arity[base_callsite_key("edge_leaf")][0]
    bucket.size.should eq(1)

    malformed = CallsiteArgs.new(types, [false], nil)
    pending_callsite_compatible_with_replay?(absent, malformed).should be_false
    ordinary_active_body_callsite?(malformed).should be_false
    pending_callsite_compatible_with_replay?(explicit, CallsiteArgs.new(types, nil, nil, has_block: true)).should be_false
    pending_callsite_compatible_with_replay?(explicit, CallsiteArgs.new(types, nil, nil, selected_target: "other")).should be_false
    with_default = CallsiteArgs.new(types, nil, nil, has_named_args: true, named_arg_names: ["flag"])
    pending_callsite_compatible_with_replay?(explicit, with_default).should be_false
    source = __test_exact_source("edge_leaf")
    binding = SourceCallBinding.new("edge_leaf", source.source_def, source.source_arena, [] of SourceCallArgument?)
    bound = CallsiteArgs.new(types, nil, nil, source_binding: binding)
    pending_callsite_compatible_with_replay?(explicit, bound).should be_false
  end

  def __test_reconciled_force_lower_argument_facts : Nil
    types = [TypeRef::BOOL]
    kinds = [false]
    plain = CallsiteArgs.new(types, kinds, nil)
    facts = [SourceCallArgument.new(TypeRef::BOOL, false).as(SourceCallArgument?)]
    enriched = CallsiteArgs.new(types, kinds, nil, source_argument_facts: facts)
    reconciled_force_lower_callsite(nil, plain).should eq(plain)
    reconciled_force_lower_callsite(plain, enriched).should eq(enriched)
    reconciled_force_lower_callsite(enriched, plain).should eq(enriched)

    object_facts = [SourceCallArgument.new(TypeRef::BOOL, true).as(SourceCallArgument?)]
    object_kind = CallsiteArgs.new(types, kinds, nil, source_argument_facts: object_facts)
    unknown = CallsiteArgs.new(types, nil, nil)
    [object_kind, unknown].each do |other|
      reconciled_force_lower_callsite(enriched, other).should be_nil
      reconciled_force_lower_callsite(other, enriched).should be_nil
    end
  end

  def __test_pending_replay_callsite_compatible?(change : Symbol) : Bool
    types = [TypeRef::INT32, TypeRef::BOOL]
    facts = [
      SourceCallArgument.new(TypeRef::INT32, false).as(SourceCallArgument?),
      SourceCallArgument.new(TypeRef::BOOL, false).as(SourceCallArgument?),
    ]
    pending_facts = nil.as(Array(SourceCallArgument?)?)
    pending_literals = [false, false].as(Array(Bool)?)
    replay_facts = facts
    replay_literals = [false, false]
    pending_enum_names = nil.as(Array(String?)?)
    replay_enum_names = nil.as(Array(String?)?)
    replay_target = nil.as(String?)
    pending_target = nil.as(String?)
    pending_binding = nil.as(SourceCallBinding?)
    replay_binding = nil.as(SourceCallBinding?)

    case change
    when :compatible_plain_facts
    when :exact_facts
      pending_facts = facts
    when :literal_fact
      replay_facts = [
        SourceCallArgument.new(TypeRef::INT32, true).as(SourceCallArgument?),
        facts[1],
      ]
    when :mismatched_type_fact
      replay_facts = [
        SourceCallArgument.new(TypeRef::BOOL, false).as(SourceCallArgument?),
        facts[1],
      ]
    when :rest_fact
      replay_facts = [
        SourceCallArgument.new(TypeRef::INT32, false, [SourceCallArgument.new(TypeRef::INT32, false)]).as(SourceCallArgument?),
        facts[1],
      ]
    when :value_fact
      replay_facts = [
        SourceCallArgument.new(TypeRef::INT32, false, value_facts: [{TypeRef::INT32, true}]).as(SourceCallArgument?),
        facts[1],
      ]
    when :tuple_fact
      replay_facts = [
        SourceCallArgument.new(TypeRef::INT32, false,
          tuple_values: [SourceCallArgument.new(TypeRef::BOOL, false)]).as(SourceCallArgument?),
        facts[1],
      ]
    when :pending_source_fact_differs
      pending_facts = [
        SourceCallArgument.new(TypeRef::INT32, true).as(SourceCallArgument?),
        facts[1],
      ]
    when :literal_shell
      replay_literals = [true, false]
    when :missing_kind_vector
      pending_literals = nil
      replay_literals = nil
    when :pending_missing_kind_vector
      pending_literals = nil
    when :replay_missing_kind_vector
      replay_literals = nil
    when :short_kind_vector
      pending_literals = [false]
      replay_literals = [false]
    when :pending_short_kind_vector
      pending_literals = [false]
    when :replay_short_kind_vector
      replay_literals = [false]
    when :partial_kind_vector
      pending_literals = [false, true]
      replay_literals = [false, true]
    when :type_literal_kind_vector
      pending_literals = [true, true]
      replay_literals = [true, true]
    when :selected_target
      replay_target = "edge_leaf$Int32"
    when :selected_target_same
      pending_target = "edge_leaf$Int32"
      replay_target = pending_target
    when :enum_shape
      pending_enum_names = ["Int32", nil]
      replay_enum_names = pending_enum_names
    when :source_binding
      source = __test_exact_source("edge_leaf")
      replay_binding = SourceCallBinding.new(
        "edge_leaf", source.source_def, source.source_arena, facts,
      )
    when :source_binding_exact
      source = __test_exact_source("edge_leaf")
      pending_binding = SourceCallBinding.new(
        "edge_leaf", source.source_def, source.source_arena, facts,
      )
      replay_binding = SourceCallBinding.new(
        "edge_leaf", source.source_def, source.source_arena,
        facts.map { |fact| fact ? copy_source_call_argument_fact(fact) : nil },
      )
      pending_facts = facts
    when :source_binding_mismatch
      source = __test_exact_source("edge_leaf")
      foreign_def, _ = __test_foreign_source_pair("edge_leaf")
      pending_facts = facts
      pending_binding = SourceCallBinding.new(
        "edge_leaf", source.source_def, source.source_arena, facts,
      )
      replay_binding = SourceCallBinding.new(
        "edge_leaf", foreign_def, source.source_arena, facts,
      )
    else
      raise "unknown pending/replay callsite change: #{change}"
    end

    pending = CallsiteArgs.new(
      types, pending_literals, pending_enum_names, false, false, nil, pending_target, pending_facts, pending_binding,
    )
    replay = CallsiteArgs.new(
      types, replay_literals, replay_enum_names, false, false, nil, replay_target, replay_facts, replay_binding,
    )
    pending_callsite_compatible_with_replay?(pending, replay)
  end

  def __test_source_argument_tuple_copy_preserved? : Bool
    fact = SourceCallArgument.new(
      TypeRef::INT32, false,
      tuple_values: [SourceCallArgument.new(TypeRef::BOOL, true)],
    )
    copied = copy_source_call_argument_fact(fact)
    copied.tuple_values == fact.tuple_values && copied.tuple_values.try(&.first.type_literal) == true
  end

  def __test_source_argument_fact_key_distinguishes_tuple? : Bool
    plain = SourceCallArgument.new(TypeRef::INT32, false)
    child = SourceCallArgument.new(TypeRef::BOOL, false)
    metaclass_child = SourceCallArgument.new(TypeRef::BOOL, true)
    tuple = SourceCallArgument.new(
      TypeRef::INT32, false,
      tuple_values: [child],
    )
    metaclass_tuple = SourceCallArgument.new(
      TypeRef::INT32, false,
      tuple_values: [metaclass_child],
    )
    source_call_argument_fact_key(plain) != source_call_argument_fact_key(tuple) &&
      source_call_argument_fact_key(tuple) != source_call_argument_fact_key(metaclass_tuple) &&
      source_call_argument_fingerprint(1469598103934665603_u64, tuple) !=
        source_call_argument_fingerprint(1469598103934665603_u64, metaclass_tuple) &&
      proc_source_type_name(tuple) == "Tuple(Bool)" &&
      proc_source_type_name(metaclass_tuple) == "Tuple(Bool.class)"
  end

  def __test_retry_request_pair_matches?(change : Symbol) : Bool
    consumer = "edge_c"
    producer = "edge_a"
    producer_source = __test_exact_source(producer)
    left_replay = __test_replay_callsite(consumer)
    right_replay = left_replay
    left_pending = ExactResultPending.new(consumer, producer, producer_source)
    right_pending = ExactResultPending.new(consumer, producer, producer_source)
    left_bypass = false
    right_bypass = false

    case change
    when :same
    when :producer_body_only
      right_pending = ExactResultPending.new(consumer, producer, producer_source,
        producer_requires_result: false)
    when :consumer_body_only
      right_pending.consumer_requires_result = false
    when :producer_bypass
      right_pending = ExactResultPending.new(consumer, producer, producer_source,
        producer_bypass_inline_yield: true)
    when :consumer_bypass
      right_pending.consumer_bypass_inline_yield = true
    when :outer_bypass
      right_bypass = true
    when :source_facts
      right_replay = __test_replay_callsite_variant(consumer, :source_facts)
    when :type_map
      right_replay = __test_replay_callsite_variant(consumer, :type_map)
    when :selected_target
      right_replay = __test_replay_callsite_variant(consumer, :selected_target)
    when :registry_name
      right_replay = __test_replay_callsite_variant(consumer, :registry_name)
    when :source_def
      right_replay = __test_replay_callsite("edge_leaf")
    else
      raise "unknown retry request change: #{change}"
    end

    left = ForceLowerSuspendedRequest.new(left_pending, left_replay, left_bypass)
    right = ForceLowerSuspendedRequest.new(right_pending, right_replay, right_bypass)
    same_force_lower_work_request?(left, right)
  end

  def __test_replay_callsite_variant(name : String, change : Symbol) : ForceLowerReplayCallsite
    source = __test_exact_source(name)
    entry_map = @type_param_map.dup
    facts = nil.as(Array(SourceCallArgument?)?)
    selected_target = nil.as(String?)
    registry_name = name
    callsite = CallsiteArgs.new(
      [] of TypeRef,
      nil,
      nil,
      false,
      false,
      nil,
      name,
    )

    case change
    when :source_facts
      source_facts = [] of SourceCallArgument?
      source_facts << SourceCallArgument.new(TypeRef::INT32, false)
      facts = source_facts
    when :type_map
      entry_map["__retry_rights_test"] = "Int32"
    when :selected_target
      selected_target = "#{name}$Int32"
    when :registry_name
      registry_name = "#{name}$Int32"
    else
      raise "unknown replay callsite change: #{change}"
    end

    callsite = CallsiteArgs.new(
      [] of TypeRef,
      nil,
      nil,
      false,
      false,
      nil,
      selected_target || name,
      facts,
    )
    ForceLowerReplayCallsite.new(
      source.source_def,
      source.source_arena,
      callsite,
      entry_map,
      @current_namespace_override,
      registry_name,
      nil,
      nil,
      source,
    )
  end

  def __test_replay_callsite_with_callback(
    name : String,
    callback_source_name : String,
    callback_return : TypeRef,
  ) : ForceLowerReplayCallsite
    source = __test_exact_source(name)
    callback_source = __test_exact_source(callback_source_name)
    callsite = CallsiteArgs.new(
      [] of TypeRef,
      nil,
      nil,
      true,
      false,
      nil,
      name,
    )
    callback_callsite = CallsiteArgs.new(
      [TypeRef::INT32],
      nil,
      nil,
      false,
      false,
      nil,
      callback_source_name,
    )
    abi = RawCallbackAbi.new([TypeRef::INT32], callback_return, TypeRef::POINTER)
    callback_binding = RawCallbackSourceBinding.new(
      callback_source.source_def,
      callback_source.source_arena,
      callback_callsite,
    )
    ForceLowerReplayCallsite.new(
      source.source_def,
      source.source_arena,
      callsite,
      @type_param_map.dup,
      @current_namespace_override,
      name,
      abi,
      callback_binding,
      source,
    )
  end

  def __test_same_callback_replay?(change : Symbol) : Bool
    left = __test_replay_callsite_with_callback("edge_c", "edge_a", TypeRef::BOOL)
    right = case change
            when :same
              __test_replay_callsite_with_callback("edge_c", "edge_a", TypeRef::BOOL)
            when :abi
              __test_replay_callsite_with_callback("edge_c", "edge_a", TypeRef::INT32)
            when :callback_source
              __test_replay_callsite_with_callback("edge_c", "edge_leaf", TypeRef::BOOL)
            else
              raise "unknown callback replay change: #{change}"
            end
    same_force_lower_replay_callsite?(left, right)
  end

  def __test_try_queue_active_edge(
    consumer : String,
    producer : String,
    producer_source : ForceLowerExactSourceBinding? = nil,
  ) : Bool
    replay = __test_replay_callsite(consumer)
    source = producer_source || __test_exact_source(producer)
    pending = ExactResultPending.new(consumer, producer, source)
    begin
      retry_suspended_exact_result(pending, replay, 0, false)
      true
    rescue blocked : ExactResultPending
      false
    end
  end

  def __test_try_queue_edge_with_foreign_arena(consumer : String, producer : String) : Bool
    source = __test_exact_source(producer)
    _, foreign_arena = __test_foreign_source_pair(producer)
    changed = ForceLowerExactSourceBinding.new(source.source_def, foreign_arena, producer)
    __test_try_queue_active_edge(consumer, producer, changed)
  end

  def __test_try_queue_edge_with_foreign_def(consumer : String, producer : String) : Bool
    source = __test_exact_source(producer)
    foreign_def, _ = __test_foreign_source_pair(producer)
    changed = ForceLowerExactSourceBinding.new(foreign_def, source.source_arena, producer)
    __test_try_queue_active_edge(consumer, producer, changed)
  end

  def __test_try_queue_edge_with_fully_foreign_receipt(consumer : String, producer : String) : Bool
    foreign_def, foreign_arena = __test_foreign_source_pair(producer)
    changed = ForceLowerExactSourceBinding.new(foreign_def, foreign_arena, producer)
    __test_try_queue_active_edge(consumer, producer, changed)
  end

  def __test_active_edge_count(consumer : String, producer : String) : Int32
    @force_lower_result_suspensions.count { |edge| edge == {consumer, producer} }
  end

  def __test_queued_suspended_edge_count(consumer : String, producer : String) : Int32
    @force_lower_retry_work.count do |request|
      request.is_a?(ForceLowerSuspendedRequest) &&
        request.pending.consumer == consumer && request.pending.producer == producer
    end
  end

  def __test_first_queued_edge_waits_for_producer? : Bool
    request = @force_lower_retry_work.first? || return false
    force_lower_retry_waits_for_queued_producer?(request)
  end

  def __test_first_queued_edge_source_current? : Bool
    request = @force_lower_retry_work.first? || return false
    force_lower_retry_source_current?(request)
  end

  def __test_foreign_source_pair(name : String) : Tuple(Adamas::Compiler::Frontend::DefNode, Adamas::Compiler::Frontend::ArenaLike)
    source = "def #{name}; 66; end"
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.should be_empty
    arena = program.arena
    foreign_def = nil.as(Adamas::Compiler::Frontend::DefNode?)
    program.roots.each do |id|
      node = arena[id]
      foreign_def = node if node.is_a?(Adamas::Compiler::Frontend::DefNode)
    end
    {foreign_def || raise("missing foreign Def"), arena}
  end
end

private def force_lower_active_edge_graph_fixture : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    def edge_leaf
      65
    end
    def edge_a
      edge_b
    end
    def edge_b
      edge_leaf
    end
    def edge_c
      edge_a
    end
    def edge_shared
      edge_leaf
    end
    def edge_cycle2_a
      edge_cycle2_b
    end
    def edge_cycle2_b
      edge_cycle2_a
    end
    def edge_cycle3_a
      edge_cycle3_b
    end
    def edge_cycle3_b
      edge_cycle3_c
    end
    def edge_cycle3_c
      edge_cycle3_a
    end
    def edge_left
      edge_shared
    end
    def edge_right
      edge_shared
    end
    def edge_diamond
      edge_left
      edge_right
    end
    def edge_pending_parent
      1
    end
    def edge_pending_child
      2
    end
    def edge_pending_sibling
      3
    end
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "/tmp/force_lower_active_edge_graph_spec.cr"},
  )
  converter.no_prelude = true
  program.roots.each do |id|
    node = arena[id]
    converter.register_function(node) if node.is_a?(Adamas::Compiler::Frontend::DefNode)
  end
  %w(
    edge_leaf edge_a edge_b edge_c edge_shared
    edge_cycle2_a edge_cycle2_b edge_cycle3_a edge_cycle3_b edge_cycle3_c
    edge_left edge_right edge_diamond
  ).each do |name|
    converter.__test_materialize_active_edge_function(name)
  end
  converter
end

describe "exact source retry graph admission" do
  it "coalesces only requests with the same complete demand and replay recipe" do
    converter = force_lower_active_edge_graph_fixture
    converter.__test_retry_request_pair_matches?(:same).should be_true

    %i(
      producer_body_only
      consumer_body_only
      producer_bypass
      consumer_bypass
      outer_bypass
      source_facts
      type_map
      selected_target
      registry_name
      source_def
    ).each do |change|
      converter.__test_retry_request_pair_matches?(change).should be_false
    end
  end

  it "runs a ready sibling while the suspended root still needs an active producer" do
    force_lower_active_edge_graph_fixture.__test_blocked_retry_drains_independent_sibling
  end

  it "retains callback ABI and callback source in replay identity" do
    converter = force_lower_active_edge_graph_fixture
    converter.__test_same_callback_replay?(:same).should be_true
    converter.__test_same_callback_replay?(:abi).should be_false
    converter.__test_same_callback_replay?(:callback_source).should be_false
  end

  it "keeps one replay and discovery identity for zero positional argument kinds" do
    force_lower_active_edge_graph_fixture.__test_nilary_callsite_kind_evidence
  end

  it "admits only a redundant positional-fact enrichment of the pending callsite" do
    converter = force_lower_active_edge_graph_fixture
    converter.__test_pending_replay_callsite_compatible?(:compatible_plain_facts).should be_true
    converter.__test_pending_replay_callsite_compatible?(:exact_facts).should be_true

    %i(
      literal_fact
      mismatched_type_fact
      rest_fact
      value_fact
      tuple_fact
      pending_source_fact_differs
      literal_shell
      missing_kind_vector
      pending_missing_kind_vector
      replay_missing_kind_vector
      short_kind_vector
      pending_short_kind_vector
      replay_short_kind_vector
      partial_kind_vector
      type_literal_kind_vector
      selected_target
      selected_target_same
      enum_shape
      source_binding
      source_binding_mismatch
    ).each do |change|
      converter.__test_pending_replay_callsite_compatible?(change).should be_false
    end
    converter.__test_pending_replay_callsite_compatible?(:source_binding_exact).should be_true
  end

  it "replays with the complete positional evidence in either discovery order" do
    force_lower_active_edge_graph_fixture.__test_reconciled_force_lower_argument_facts
  end

  it "preserves tuple source facts through replay copies and fingerprints" do
    converter = force_lower_active_edge_graph_fixture
    converter.__test_source_argument_tuple_copy_preserved?.should be_true
    converter.__test_source_argument_fact_key_distinguishes_tuple?.should be_true
  end

  it "admits the nested C to A to B chain while retaining both exact edges" do
    converter = force_lower_active_edge_graph_fixture
    converter.__test_start_active_edge_graph

    converter.__test_try_queue_active_edge("edge_a", "edge_b").should be_true
    converter.__test_try_queue_active_edge("edge_c", "edge_a").should be_true

    converter.__test_active_edge_count("edge_a", "edge_b").should eq(1)
    converter.__test_active_edge_count("edge_c", "edge_a").should eq(1)
    converter.__test_queued_suspended_edge_count("edge_a", "edge_b").should eq(1)
    converter.__test_queued_suspended_edge_count("edge_c", "edge_a").should eq(1)
    converter.__test_stop_active_edge_graph
  end

  it "coalesces an equivalent duplicate edge but rejects the same edge with changed source receipts" do
    converter = force_lower_active_edge_graph_fixture
    converter.__test_start_active_edge_graph
    converter.__test_try_queue_active_edge("edge_c", "edge_a").should be_true

    # Repeating the same edge with the same registered Def/Arena is idempotent.
    converter.__test_try_queue_active_edge("edge_c", "edge_a").should be_true
    converter.__test_active_edge_count("edge_c", "edge_a").should eq(1)
    converter.__test_queued_suspended_edge_count("edge_c", "edge_a").should eq(1)

    # A same-name Def parsed into a different arena is not the same receipt.
    converter.__test_try_queue_edge_with_foreign_arena("edge_c", "edge_a").should be_false
    converter.__test_try_queue_edge_with_foreign_def("edge_c", "edge_a").should be_false
    converter.__test_active_edge_count("edge_c", "edge_a").should eq(1)
    converter.__test_queued_suspended_edge_count("edge_c", "edge_a").should eq(1)
    converter.__test_stop_active_edge_graph
  end

  it "rejects actual two-node and three-node dependency cycles" do
    two = force_lower_active_edge_graph_fixture
    two.__test_start_active_edge_graph
    two.__test_try_queue_active_edge("edge_cycle2_a", "edge_cycle2_b").should be_true
    two.__test_try_queue_active_edge("edge_cycle2_b", "edge_cycle2_a").should be_false
    two.__test_active_edge_count("edge_cycle2_a", "edge_cycle2_b").should eq(1)
    two.__test_active_edge_count("edge_cycle2_b", "edge_cycle2_a").should eq(0)
    two.__test_stop_active_edge_graph

    three = force_lower_active_edge_graph_fixture
    three.__test_start_active_edge_graph
    three.__test_try_queue_active_edge("edge_cycle3_a", "edge_cycle3_b").should be_true
    three.__test_try_queue_active_edge("edge_cycle3_b", "edge_cycle3_c").should be_true
    three.__test_try_queue_active_edge("edge_cycle3_c", "edge_cycle3_a").should be_false
    three.__test_active_edge_count("edge_cycle3_a", "edge_cycle3_b").should eq(1)
    three.__test_active_edge_count("edge_cycle3_b", "edge_cycle3_c").should eq(1)
    three.__test_active_edge_count("edge_cycle3_c", "edge_cycle3_a").should eq(0)
    three.__test_stop_active_edge_graph
  end

  it "retains a diamond with two consumers sharing one exact producer" do
    converter = force_lower_active_edge_graph_fixture
    converter.__test_start_active_edge_graph

    converter.__test_try_queue_active_edge("edge_diamond", "edge_left").should be_true
    converter.__test_try_queue_active_edge("edge_diamond", "edge_right").should be_true
    converter.__test_try_queue_active_edge("edge_left", "edge_shared").should be_true
    converter.__test_try_queue_active_edge("edge_right", "edge_shared").should be_true

    converter.__test_active_edge_count("edge_diamond", "edge_left").should eq(1)
    converter.__test_active_edge_count("edge_diamond", "edge_right").should eq(1)
    converter.__test_active_edge_count("edge_left", "edge_shared").should eq(1)
    converter.__test_active_edge_count("edge_right", "edge_shared").should eq(1)
    converter.__test_stop_active_edge_graph
  end

  it "does not treat a queued stale Def/Arena edge as current or as a live dependency" do
    converter = force_lower_active_edge_graph_fixture
    converter.__test_start_active_edge_graph
    converter.__test_try_queue_edge_with_fully_foreign_receipt("edge_left", "edge_shared").should be_true
    converter.__test_first_queued_edge_source_current?.should be_false
    converter.__test_first_queued_edge_waits_for_producer?.should be_false
    converter.__test_stop_active_edge_graph
  end

  it "relays multiple driver-owned nested pending edges through their exact live parent" do
    converter = force_lower_active_edge_graph_fixture
    converter.__test_start_active_edge_graph
    parent, child, child_replay = converter.__test_start_nested_pending_capture(
      "edge_pending_parent", "edge_pending_child",
    )
    sibling_capture, sibling_replay = converter.__test_add_nested_pending_child(
      parent, "edge_pending_sibling",
    )
    sibling_capture.parent.try(&.same?(parent)).should be_true

    pending = converter.__test_nested_pending(child)
    sibling_pending = converter.__test_nested_pending(sibling_capture)
    converter.__test_retry_nested_pending(pending, child_replay).should be_false
    converter.__test_retry_nested_pending(sibling_pending, sibling_replay).should be_false

    converter.__test_provisional_dependency_names(parent.name).should eq([
      "edge_pending_child", "edge_pending_sibling",
    ])
    converter.__test_queued_suspended_edge_count("edge_pending_child", "edge_leaf").should eq(1)
    converter.__test_queued_suspended_edge_count("edge_pending_sibling", "edge_leaf").should eq(1)
    converter.__test_relay_preserves_nested_pending?(parent, pending).should be_true
    converter.__test_relay_preserves_nested_pending?(parent, sibling_pending).should be_true
    converter.__test_stop_nested_pending_capture(parent.name)
  end

  it "rejects replaced or stale parents and a different child replay generation" do
    replaced = force_lower_active_edge_graph_fixture
    replaced.__test_start_active_edge_graph
    parent, child, replay = replaced.__test_start_nested_pending_capture(
      "edge_pending_parent", "edge_pending_child",
    )
    pending = replaced.__test_nested_pending(child)
    replaced.__test_replace_active_nested_parent(parent)
    replaced.__test_retry_nested_pending(pending, replay).should be_false
    replaced.__test_provisional_dependency_names(parent.name).should be_empty
    replaced.__test_relay_preserves_nested_pending?(parent, pending).should be_false
    replaced.__test_stop_nested_pending_capture(parent.name)

    stale = force_lower_active_edge_graph_fixture
    stale.__test_start_active_edge_graph
    stale_parent, stale_child, stale_replay = stale.__test_start_nested_pending_capture(
      "edge_pending_parent", "edge_pending_child",
    )
    stale_pending = stale.__test_nested_pending(stale_child)
    stale.__test_retry_with_stale_nested_parent_source(
      stale_parent.name, stale_pending, stale_replay,
    ).should be_false
    stale.__test_provisional_dependency_names(stale_parent.name).should be_empty
    stale.__test_relay_preserves_nested_pending?(stale_parent, stale_pending).should be_false
    stale.__test_stop_nested_pending_capture(stale_parent.name)

    other_generation = force_lower_active_edge_graph_fixture
    other_generation.__test_start_active_edge_graph
    generation_parent, generation_child, generation_replay = other_generation.__test_start_nested_pending_capture(
      "edge_pending_parent", "edge_pending_child",
    )
    generation_pending = other_generation.__test_nested_pending(generation_child)
    changed_replay = other_generation.__test_replay_callsite_variant(
      generation_child.name, :source_facts,
    )
    other_generation.__test_retry_nested_pending(generation_pending, changed_replay).should be_false
    other_generation.__test_provisional_dependency_names(generation_parent.name).should be_empty
    other_generation.__test_relay_preserves_nested_pending?(generation_parent, generation_pending).should be_false
    other_generation.__test_stop_nested_pending_capture(generation_parent.name)
  end
end
