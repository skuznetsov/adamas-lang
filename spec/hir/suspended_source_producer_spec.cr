require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_separate_source_producer(change : Symbol) : Tuple(Bool, Bool)
    consumer = "queued_consumer"
    dependency = "queued_consumer_dependency"
    producer = "unqueued_result_producer"
    source = __test_separate_producer_source(producer)
    replay = __test_separate_producer_replay(producer, source)
    consumer_source = __test_separate_producer_source(consumer)
    dependency_source = __test_separate_producer_source(dependency)

    # The old consumer body has an unfinished dependency with its own live
    # request. The producer is only represented by the consumer's suspension.
    @force_lower_provisional_dependencies[consumer] = Set{dependency, producer}
    @force_lower_provisional_dependencies[dependency] = Set{consumer}
    @force_lower_retry_work << ForceLowerRetryRequest.new(dependency, [consumer], false,
      __test_separate_producer_replay(dependency, dependency_source), dependency_source)

    case change
    when :no_recipe
      replay = nil
    when :conflicting_arguments
      @pending_arg_types[producer] = CallsiteArgs.new([TypeRef::INT32], nil, nil, selected_target: producer)
    end

    pending = ExactResultPending.new(consumer, producer, source, replay)
    request = ForceLowerSuspendedRequest.new(pending, __test_separate_producer_replay(consumer, consumer_source), false)
    force_lower_retry_waits_for_queued_producer?(request).should be_true
    settled_force_lower_result?(producer).should be_false
    run_force_lower_retry_driver(request).should be_false
    {settled_force_lower_result?(producer), @module.has_function_with_body?(consumer)}
  end

  private def __test_separate_producer_source(name : String) : ForceLowerExactSourceBinding
    ForceLowerExactSourceBinding.new(@function_defs[name], @function_def_arenas[name], name)
  end

  private def __test_separate_producer_replay(name : String, source : ForceLowerExactSourceBinding) : ForceLowerReplayCallsite
    callsite = CallsiteArgs.new([] of TypeRef, nil, nil, selected_target: name)
    ForceLowerReplayCallsite.new(source.source_def, source.source_arena, callsite, @type_param_map.dup,
      @current_namespace_override, name, exact_source_binding: source)
  end
end

private def separate_source_producer_fixture(producer_result : String = "true") : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    def queued_consumer : Bool
      unqueued_result_producer
      queued_consumer_dependency
    end

    def queued_consumer_dependency : Bool
      queued_consumer
    end

    def unqueued_result_producer : Bool
      #{producer_result}
    end
    CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "/tmp/suspended_source_producer_spec.cr"})
  converter.no_prelude = true
  program.roots.each do |id|
    converter.register_function(arena[id].as(Adamas::Compiler::Frontend::DefNode))
  end
  converter
end

describe "exact suspended producer work" do
  it "materializes the exact producer while leaving the consumer blocked" do
    separate_source_producer_fixture.__test_separate_source_producer(:current).should eq({true, false})
  end

  it "keeps waiting if the producer has no retained callsite" do
    separate_source_producer_fixture.__test_separate_source_producer(:no_recipe).should eq({false, false})
  end

  it "does not replace a different pending producer callsite" do
    separate_source_producer_fixture.__test_separate_source_producer(:conflicting_arguments).should eq({false, false})
  end

  it "enforces the completed producer's declared result on replay" do
    expect_raises(Adamas::HIR::LoweringError, /unqueued_result_producer.*Bool.*Int32/) do
      separate_source_producer_fixture("42").__test_separate_source_producer(:current)
    end
  end
end
