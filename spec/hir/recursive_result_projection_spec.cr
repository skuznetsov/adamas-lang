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
    index = open_recursive_struct_result
    if index
      index.should eq(0)
      settled_force_lower_result?(producer).should be_false
      @force_lower_provisional_dependencies[consumer].should eq(Set{producer})
      recursive_struct_result_available?(selected).should be_true
      @module.function_by_name(producer).not_nil!.source_return_result_receipt = nil
      recursive_struct_result_available?(selected).should be_false
    end
    !index.nil?
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
    ticket = use.begin_emission_ticket
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
      ticket = use.begin_emission_ticket
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
    obsolete_ticket = use.begin_emission_ticket
    use.clear_body_emissions
    current_ticket = use.begin_emission_ticket
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
    ticket = use.begin_emission_ticket
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
end
