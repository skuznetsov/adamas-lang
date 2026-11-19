require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_retry_handoff_work(name : String) : ForceLowerWorkRequest
    source = __test_retry_handoff_source(name)
    replay = __test_retry_handoff_replay(name)
    ForceLowerRetryRequest.new(name, ["handoff_dependency"], false, replay, source, true)
  end

  def __test_retry_handoff_pending(
    consumer : String = "handoff_consumer",
    producer : String = "handoff_leaf",
  ) : ForceLowerSuspendedRequest
    source = __test_retry_handoff_source(producer)
    producer_replay = __test_retry_handoff_replay(producer)
    pending = ExactResultPending.new(
      consumer,
      producer,
      source,
      producer_replay,
      producer_requires_result: false,
      producer_bypass_inline_yield: false,
    )
    ForceLowerSuspendedRequest.new(pending, __test_retry_handoff_replay(consumer), false)
  end

  def __test_retry_handoff_round_trip?(work_name : String = "handoff_leaf") : Bool
    request = __test_retry_handoff_pending
    work = __test_retry_handoff_work(work_name)
    @force_lower_retry_work.clear
    @force_lower_return_type_depth = 1
    enqueue_force_lower_retry_work(work).should be_true
    handoff = ForceLowerRetryWorkHandoff.new
    preserve_force_lower_retry_work_for_pending(request.pending, handoff)
    @force_lower_retry_work.clear

    request.pending.retry_work_handoff.should be(handoff)
    handoff.pending_requests.size.should eq(1)
    @force_lower_return_type_depth = 0
    restore_force_lower_retry_work_from_handoff(handoff)
    @force_lower_retry_work.size.should eq(1)
    same_force_lower_work_request?(@force_lower_retry_work.first, work)
  ensure
    @force_lower_retry_work.clear
  end

  def __test_retry_handoff_is_scoped_to_exact_pending? : Bool
    owner = __test_retry_handoff_pending
    work = __test_retry_handoff_work("handoff_leaf")
    @force_lower_retry_work.clear
    enqueue_force_lower_retry_work(work)
    handoff = ForceLowerRetryWorkHandoff.new
    preserve_force_lower_retry_work_for_pending(owner.pending, handoff)
    @force_lower_retry_work.clear

    sibling = __test_retry_handoff_pending("handoff_sibling", "handoff_leaf")
    force_lower_retry_handoff_for_pending(sibling.pending).should be_nil
    @force_lower_retry_work.empty?
  ensure
    @force_lower_retry_work.clear
  end

  def __test_retry_handoff_drops_stale_work? : Bool
    request = __test_retry_handoff_pending
    work = __test_retry_handoff_work("handoff_leaf")
    @force_lower_retry_work.clear
    enqueue_force_lower_retry_work(work)
    handoff = ForceLowerRetryWorkHandoff.new
    preserve_force_lower_retry_work_for_pending(request.pending, handoff)
    @force_lower_retry_work.clear

    old_def = @function_defs["handoff_leaf"]
    old_arena = @function_def_arenas["handoff_leaf"]
    foreign_arena, foreign_def = __test_retry_handoff_foreign_source
    @function_defs["handoff_leaf"] = foreign_def
    set_function_def_arena("handoff_leaf", foreign_arena)
    begin
      restore_force_lower_retry_work_from_handoff(handoff)
      @force_lower_retry_work.empty? && handoff.pending_requests.empty?
    ensure
      @function_defs["handoff_leaf"] = old_def
      set_function_def_arena("handoff_leaf", old_arena)
    end
  ensure
    @force_lower_retry_work.clear
  end

  def __test_retry_handoff_waits_for_shallower_driver? : Bool
    owner = __test_retry_handoff_pending
    work = __test_retry_handoff_work("handoff_leaf")
    handoff = ForceLowerRetryWorkHandoff.new
    @force_lower_return_type_depth = 2
    record_force_lower_retry_attempt(handoff, work, @force_lower_return_type_depth)
    enqueue_force_lower_retry_work(work)
    preserve_force_lower_retry_work_for_pending(owner.pending, handoff)
    @force_lower_retry_work.clear

    [2, 3].each do |depth|
      @force_lower_return_type_depth = depth
      restore_force_lower_retry_work_from_handoff(handoff)
      @force_lower_retry_work.should be_empty
      handoff.pending_requests.size.should eq(1)
    end
    @force_lower_return_type_depth = 1
    restore_force_lower_retry_work_from_handoff(handoff)
    restore_force_lower_retry_work_from_handoff(handoff)
    @force_lower_retry_work.size == 1 && handoff.pending_requests.empty?
  ensure
    @force_lower_return_type_depth = 0
    @force_lower_retry_work.clear
  end

  def __test_unattempted_sibling_survives_second_unwind? : Bool
    owner = __test_retry_handoff_pending
    first = __test_retry_handoff_work("handoff_leaf")
    second = __test_retry_handoff_work("handoff_sibling")
    handoff = ForceLowerRetryWorkHandoff.new
    @force_lower_return_type_depth = 2
    enqueue_force_lower_retry_work(first)
    enqueue_force_lower_retry_work(second)
    preserve_force_lower_retry_work_for_pending(owner.pending, handoff)
    @force_lower_retry_work.clear

    # Queued work can move to a sibling driver at the same native depth.
    @force_lower_return_type_depth = 2
    restore_force_lower_retry_work_from_handoff(handoff)
    attempted = @force_lower_retry_work.pop
    same_force_lower_work_request?(attempted, second).should be_true
    record_force_lower_retry_attempt(handoff, attempted, @force_lower_return_type_depth)
    preserve_force_lower_retry_work_for_pending(owner.pending, handoff)
    @force_lower_retry_work.clear

    @force_lower_return_type_depth = 0
    restore_force_lower_retry_work_from_handoff(handoff)
    @force_lower_retry_work.size == 1 && same_force_lower_work_request?(@force_lower_retry_work.first, first)
  ensure
    @force_lower_return_type_depth = 0
    @force_lower_retry_work.clear
  end

  def __test_retry_handoff_link?(transplant : Bool) : Bool
    middle = "handoff_consumer"
    child_name = transplant ? "handoff_sibling" : middle
    leaf = __test_retry_handoff_pending(child_name, "handoff_leaf").pending
    capture = ForceLowerReplayCapture.new(child_name, nil)
    capture.binding = __test_retry_handoff_replay(child_name)
    leaf.consumer_capture = capture
    leaf.retry_work_handoff = ForceLowerRetryWorkHandoff.new
    parent = ExactResultPending.new("handoff_sibling", middle, __test_retry_handoff_source(middle),
      __test_retry_handoff_replay(middle), false, false, leaf)
    !!force_lower_retry_handoff_for_pending(parent)
  end

  def __test_schedule_settled_retry_sibling(independent : Bool) : Nil
    blocked = __test_retry_handoff_pending("handoff_consumer", "handoff_waiting")
    dependent = __test_retry_handoff_pending("handoff_sibling", "handoff_leaf")
    ready = __test_retry_handoff_pending("handoff_ready", "handoff_leaf")
    replay_force_lower_callsite("handoff_leaf", __test_retry_handoff_replay("handoff_leaf"),
      false, requires_result: false)
    settled_force_lower_producer?(dependent.pending).should be_true
    settled_force_lower_producer?(blocked.pending).should be_false

    # The blocked consumer has left the queue during dispatch. Its dependent
    # sibling's own immediate producer is ready, but the sibling cannot run
    # after the scheduler restores the blocked consumer.
    @force_lower_provisional_dependencies[dependent.name] = Set{blocked.name}
    enqueue_force_lower_retry_work(ready) if independent
    enqueue_force_lower_retry_work(dependent)
    force_lower_retry_waits_for_queued_producer?(dependent).should be_false

    handoff = ForceLowerRetryWorkHandoff.new
    record_force_lower_retry_attempt(handoff, blocked, @force_lower_return_type_depth)
    schedule_settled_retry_sibling(blocked, handoff).should eq(independent)
    if independent
      @force_lower_retry_work.should eq([blocked, dependent, ready])
      force_lower_retry_waits_for_queued_producer?(dependent).should be_true
      force_lower_retry_waits_for_queued_producer?(ready).should be_false
    else
      @force_lower_retry_work.should eq([dependent])
    end
  ensure
    @force_lower_retry_work.clear
    @force_lower_provisional_dependencies.delete("handoff_sibling")
  end

  private def __test_retry_handoff_source(name : String) : ForceLowerExactSourceBinding
    source_def = @function_defs[name]? || raise "missing retry handoff Def: #{name}"
    source_arena = @function_def_arenas[name]? || raise "missing retry handoff arena: #{name}"
    ForceLowerExactSourceBinding.new(source_def, source_arena, name)
  end

  private def __test_retry_handoff_replay(name : String) : ForceLowerReplayCallsite
    source = __test_retry_handoff_source(name)
    callsite = CallsiteArgs.new([] of TypeRef, nil, nil, selected_target: name)
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

  private def __test_retry_handoff_foreign_source : {Adamas::Compiler::Frontend::ArenaLike, Adamas::Compiler::Frontend::DefNode}
    source = "def handoff_leaf\n  99\nend"
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.should be_empty
    arena = program.arena
    {arena, arena[program.roots.first].as(Adamas::Compiler::Frontend::DefNode)}
  end
end

private def retry_handoff_fixture
  source = <<-CRYSTAL
    def handoff_leaf
      7
    end

    def handoff_consumer
      handoff_leaf
    end

    def handoff_sibling
      handoff_leaf
    end

    def handoff_waiting
      9
    end

    def handoff_ready
      handoff_leaf
    end
    CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "/tmp/force_lower_retry_handoff_spec.cr"},
  )
  converter.no_prelude = true
  program.roots.each do |id|
    node = arena[id]
    converter.register_function(node) if node.is_a?(Adamas::Compiler::Frontend::DefNode)
  end
  converter
end

describe "exact pending retry work handoff" do
  it "does not reschedule a sibling that waits for the restored request" do
    retry_handoff_fixture.__test_schedule_settled_retry_sibling(independent: false)
  end

  it "schedules an independent ready sibling even when a dependent sibling appears ready" do
    retry_handoff_fixture.__test_schedule_settled_retry_sibling(independent: true)
  end

  it "restores only current retry work from the pending that owns it" do
    retry_handoff_fixture.__test_retry_handoff_round_trip?.should be_true
  end

  it "does not expose an owner's work to an unrelated sibling pending" do
    retry_handoff_fixture.__test_retry_handoff_is_scoped_to_exact_pending?.should be_true
  end

  it "requires an unbroken source replay chain before importing a descendant's work" do
    converter = retry_handoff_fixture
    converter.__test_retry_handoff_link?(transplant: false).should be_true
    converter.__test_retry_handoff_link?(transplant: true).should be_false
  end

  it "drops work after its exact Def and arena receipt becomes stale" do
    retry_handoff_fixture.__test_retry_handoff_drops_stale_work?.should be_true
  end

  it "retries an already attempted obligation once at a shallower boundary" do
    retry_handoff_fixture.__test_retry_handoff_waits_for_shallower_driver?.should be_true
  end

  it "retains an unattempted sibling when an imported request unwinds again" do
    retry_handoff_fixture.__test_unattempted_sibling_survives_second_unwind?.should be_true
  end
end
