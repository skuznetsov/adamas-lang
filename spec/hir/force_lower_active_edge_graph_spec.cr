require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_materialize_active_edge_function(name : String) : Nil
    lower_function_if_needed(name)
    @function_defs.has_key?(name).should be_true
    @function_def_arenas.has_key?(name).should be_true
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

  it "retains callback ABI and callback source in replay identity" do
    converter = force_lower_active_edge_graph_fixture
    converter.__test_same_callback_replay?(:same).should be_true
    converter.__test_same_callback_replay?(:abi).should be_false
    converter.__test_same_callback_replay?(:callback_source).should be_false
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
end
