require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_queued_tuple_function_type(name : String) : String
    function = @module.function_by_name(name) || raise "missing tuple function #{name}"
    get_type_name_from_ref(function.return_type)
  end

  def __test_queued_source_result_demand(
    *,
    requires_result : Bool = true,
    stale_source : Bool = false,
    driver_active : Bool = true,
  ) : Tuple(Bool, Bool, Bool, Bool)
    target = "QueuedTupleSource.value"
    consumer = "queued_tuple_consumer"
    source_def = @function_defs[target]? || raise "missing target source Def"
    source_arena = @function_def_arenas[target]? || raise "missing target source arena"
    source = ForceLowerExactSourceBinding.new(source_def, source_arena, target)
    callsite = CallsiteArgs.new([] of TypeRef, nil, nil, selected_target: target)
    replay = ForceLowerReplayCallsite.new(
      source_def, source_arena, callsite, @type_param_map.dup,
      @current_namespace_override, target, exact_source_binding: source,
    )
    queued_source = if stale_source
                      foreign_name = "QueuedTupleForeign.value"
                      foreign_def = @function_defs[foreign_name]? || raise "missing foreign source Def"
                      foreign_arena = @function_def_arenas[foreign_name]? || raise "missing foreign source arena"
                      ForceLowerExactSourceBinding.new(foreign_def, foreign_arena, target)
                    else
                      source
                    end
    @force_lower_retry_work.clear
    @force_lower_retry_work << ForceLowerRetryRequest.new(
      target, [] of String, false, replay, queued_source, requires_result,
    )
    @force_lower_retry_driver_active = driver_active

    consumer_def = @function_defs[consumer]? || raise "missing consumer source Def"
    consumer_arena = @function_def_arenas[consumer]? || raise "missing consumer source arena"
    consumer_source = ForceLowerExactSourceBinding.new(consumer_def, consumer_arena, consumer)
    consumer_replay = ForceLowerReplayCallsite.new(
      consumer_def, consumer_arena,
      CallsiteArgs.new([] of TypeRef, nil, nil, selected_target: consumer),
      @type_param_map.dup, @current_namespace_override, consumer,
      exact_source_binding: consumer_source,
    )
    capture = ForceLowerReplayCapture.new(consumer, nil)
    capture.binding = consumer_replay
    @force_lower_active_replay_captures[consumer] = capture
    @pending_arg_types[consumer] = consumer_replay.callsite

    # Model an unfinished source body whose HIR shell exists but whose exact
    # result has not settled. The queued replay is the surviving obligation;
    # no producer dependency edge is available to the consumer.
    producer = @module.function_by_name(target) || @module.create_function(target, TypeRef::VOID)
    producer_context = LoweringContext.new(producer, @module, @arena)
    producer_context.emit(Literal.new(producer_context.next_id, TypeRef::INT32, 42_i64))
    set_function_state(target, FunctionLoweringState::NotStarted)
    @force_lower_provisional_dependencies.delete(target)

    function = @module.function_by_name(consumer) || @module.create_function(consumer, TypeRef::VOID)
    ctx = LoweringContext.new(function, @module, @arena)
    ctx.source_result_replay_consumer = consumer
    published = @force_lower_provisional_dependencies[consumer]?.try(&.includes?(target)) || false

    pending_seen = false
    call_returned = false
    begin
      consumer_body = consumer_def.body || raise "missing source body for #{consumer}"
      call_id = consumer_body.last? || raise "missing source call expression for #{consumer}"
      call_node = consumer_arena[call_id].as?(Adamas::Compiler::Frontend::CallNode) ||
                  raise "expected call expression in #{consumer} body"
      lower_call(ctx, call_node, call_id)
      call_returned = true
    rescue pending : ExactResultPending
      pending_seen = pending.consumer == consumer && pending.producer == target &&
                     same_force_lower_exact_source_binding?(pending.producer_source, source)
    end

    queued_entry_current = @force_lower_retry_work.any? do |request|
      request.name == target && force_lower_retry_requires_result?(request) &&
        force_lower_retry_source_current?(request)
    end
    published = @force_lower_provisional_dependencies[consumer]?.try(&.includes?(target)) || false
    {published, pending_seen, call_returned, queued_entry_current}
  ensure
    @force_lower_retry_work.clear
    @force_lower_retry_driver_active = false
    @force_lower_active_replay_captures.delete("queued_tuple_consumer")
    @pending_arg_types.delete("queued_tuple_consumer")
    @force_lower_provisional_dependencies.delete("queued_tuple_consumer")
    if @module.function_by_name("queued_tuple_consumer")
      remove_hir_function("queued_tuple_consumer")
    end
  end
end

private def queued_source_result_fixture : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    class QueuedTupleSource
      def self.value
        {1, "ok"}
      end
    end

    def queued_tuple_consumer : Tuple(Int32, String)
      QueuedTupleSource.value()
    end

    class QueuedTupleForeign
      def self.value : Tuple(Int32, String)
        {2, "foreign"}
      end
    end
    CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "/tmp/queued_source_result_demand_spec.cr"},
  )
  converter.no_prelude = true
  program.roots.each do |id|
    case node = arena[id]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
    end
  end
  converter
end

private def queued_tuple_syntax_fixture(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "/tmp/queued_tuple_syntax_spec.cr"},
  )
  converter.no_prelude = true
  main = [] of UInt64
  program.roots.each do |id|
    node = arena[id]
    if node.is_a?(Adamas::Compiler::Frontend::DefNode)
      converter.register_function(node)
    else
      main << id.index.to_u64
    end
  end
  converter.lower_main(main)
  converter.flush_pending_functions
  converter
end

describe "queued exact source result demand" do
  it "publishes and suspends a strict call on its current exact source retry" do
    published, pending, call_returned, queued_entry_current = queued_source_result_fixture.__test_queued_source_result_demand(
    )
    published.should be_true
    pending.should be_true
    call_returned.should be_false
    queued_entry_current.should be_true
  end

  it "does not treat body-only work as a source result" do
    published, pending, call_returned, queued_entry_current = queued_source_result_fixture.__test_queued_source_result_demand(
      requires_result: false,
    )
    published.should be_false
    pending.should be_false
    call_returned.should be_true
    queued_entry_current.should be_false
  end

  it "rejects a queued request bound to a different source Def" do
    published, pending, call_returned, queued_entry_current = queued_source_result_fixture.__test_queued_source_result_demand(
      stale_source: true,
    )
    published.should be_false
    pending.should be_false
    call_returned.should be_true
    queued_entry_current.should be_false
  end

  it "does not import queued result work outside the retry driver" do
    published, pending, call_returned, queued_entry_current = queued_source_result_fixture.__test_queued_source_result_demand(
      driver_active: false,
    )
    published.should be_false
    pending.should be_false
    call_returned.should be_true
    queued_entry_current.should be_true
  end

  it "preserves tuple results through parenthesized calls and destructuring" do
    converter = queued_tuple_syntax_fixture(<<-CRYSTAL)
      def queued_pair
        {41, "answer"}
      end

      def queued_parenthesized
        (queued_pair)
      end

      def queued_destructured
        left, right = (queued_pair)
        {left, right}
      end

      queued_parenthesized
      queued_destructured
      CRYSTAL
    converter.__test_queued_tuple_function_type("queued_parenthesized").should contain("Tuple")
    converter.__test_queued_tuple_function_type("queued_parenthesized").should contain("Int32")
    converter.__test_queued_tuple_function_type("queued_parenthesized").should contain("String")
    converter.__test_queued_tuple_function_type("queued_destructured").should contain("Tuple")
    converter.__test_queued_tuple_function_type("queued_destructured").should contain("Int32")
    converter.__test_queued_tuple_function_type("queued_destructured").should contain("String")
  end

  it "rejects a tuple destructure whose projected elements are returned in the wrong order" do
    expect_raises(Adamas::HIR::LoweringError, /must return/) do
      queued_tuple_syntax_fixture(<<-CRYSTAL)
        def queued_pair
          {41, "answer"}
        end

        def queued_wrong_element : Tuple(Int32, String)
          left, right = (queued_pair)
          {right, left}
        end

        queued_wrong_element
        CRYSTAL
    end
  end

  it "keeps strict return validation on a tuple-valued source call" do
    expect_raises(Adamas::HIR::LoweringError, /must return/) do
      queued_tuple_syntax_fixture(<<-CRYSTAL)
        def queued_pair
          {41, "answer"}
        end

        def queued_wrong_return : Tuple(String, String)
          queued_pair
        end

        queued_wrong_return
        CRYSTAL
    end
  end
end
