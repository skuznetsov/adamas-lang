require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private record ActiveBodyOwnerObservation,
  retained : Bool,
  exact_call_owned : Bool,
  source_facts_owned : Bool,
  missing_kind_rejected : Bool,
  literal_rejected : Bool,
  block_rejected : Bool,
  named_rejected : Bool,
  callback_rejected : Bool,
  other_target_rejected : Bool,
  exact_pending_preserved : Bool,
  family_discovery_recorded : Bool

class Adamas::HIR::AstToHir
  def __test_install_active_body_owner(target : String) : {Bool, Function, String, CallsiteArgs, ForceLowerReplayCapture}
    function = @module.function_by_name(target).not_nil!
    registry_name = @function_defs.has_key?(target) ? target : strip_type_suffix(target)
    definition = @function_defs[registry_name].not_nil!
    arena = @function_def_arenas[registry_name].not_nil!
    offset = function.params.first?.try(&.name) == "self" ? 1 : 0
    formal_types = function.params.skip(offset).map(&.type)
    ordinary_callsite = CallsiteArgs.new(
      formal_types,
      Array.new(formal_types.size, false),
      nil,
    )
    source = ForceLowerExactSourceBinding.new(definition, arena, registry_name)
    replay = ForceLowerReplayCallsite.new(
      definition, arena, ordinary_callsite,
      {} of String => String, nil, registry_name, nil, nil, source,
    )
    capture = ForceLowerReplayCapture.new(target, nil)
    capture.source = source
    capture.binding = replay
    @force_lower_active_replay_captures[target] = capture
    set_function_state(target, FunctionLoweringState::InProgress)
    retain_active_force_lower_body(function, definition, arena)
    {capture.active_body != nil, function, registry_name, ordinary_callsite, capture}
  end

  def __test_active_body_owner_observation(target : String) : ActiveBodyOwnerObservation
    retained, function, _registry_name, ordinary, _capture = __test_install_active_body_owner(target)
    offset = function.params.first?.try(&.name) == "self" ? 1 : 0
    formal_types = function.params.skip(offset).map(&.type)

    source_facts = [] of SourceCallArgument?
    formal_types.each { |type| source_facts << SourceCallArgument.new(type, false) }
    source_fact_callsite = CallsiteArgs.new(
      formal_types, nil, nil, false, false, nil, nil, source_facts, nil,
    )

    unknown_kind = CallsiteArgs.new(formal_types, nil, nil)
    type_literal = Array.new(formal_types.size, false)
    type_literal[0] = true unless type_literal.empty?
    literal_callsite = CallsiteArgs.new(formal_types, type_literal, nil)
    block_callsite = CallsiteArgs.new(
      formal_types, Array.new(formal_types.size, false), nil, true,
    )
    named_callsite = CallsiteArgs.new(
      formal_types, Array.new(formal_types.size, false), nil, false, true,
    )
    callback_callsite = CallsiteArgs.new(
      formal_types, Array.new(formal_types.size, false), nil, false, false, nil, target,
    )

    concrete_type = type_ref_for_name("RecursiveBodyConcreteStream")
    saved_types = formal_types.dup
    saved_types[0] = concrete_type unless saved_types.empty?
    saved_callsite = CallsiteArgs.new(saved_types, Array.new(saved_types.size, false), nil)
    @pending_arg_types[target] = saved_callsite
    base_key = base_callsite_key(target)
    @pending_arg_types_by_arity[base_key]?.try(&.delete(formal_types.size))
    @pending_arg_types_seen_by_arity[base_key]?.try(&.delete(formal_types.size))
    remember_callsite_arg_types(
      target, formal_types, nil, nil, false, false, nil, source_facts,
    )
    current_pending = @pending_arg_types[target]?

    family_entries = @pending_arg_types_by_arity[base_key]?.try do |by_arity|
      by_arity[formal_types.size]?
    end || [] of CallsiteArgs

    ActiveBodyOwnerObservation.new(
      retained,
      active_force_lower_body_owns_callsite?(target, ordinary),
      active_force_lower_body_owns_callsite?(target, source_fact_callsite),
      !active_force_lower_body_owns_callsite?(target, unknown_kind),
      !active_force_lower_body_owns_callsite?(target, literal_callsite),
      !active_force_lower_body_owns_callsite?(target, block_callsite),
      !active_force_lower_body_owns_callsite?(target, named_callsite),
      !active_force_lower_body_owns_callsite?(target, callback_callsite),
      !active_force_lower_body_owns_callsite?("#{target}_other", ordinary),
      current_pending == saved_callsite,
      family_entries.any? { |entry| entry.source_argument_facts == source_facts },
    )
  end

  def __test_active_body_mutation_rejected?(target : String, mutation : Symbol) : Bool
    retained, function, registry_name, _ordinary, _capture = __test_install_active_body_owner(target)
    return false unless retained
    original_return = function.return_type
    original_param_types = function.params.map(&.type)
    original_param_names = function.params.map(&.name)

    case mutation
    when :return_type
      function.return_type = TypeRef::INT32
      raise "return-type mutation did not apply" if function.return_type == original_return
    when :parameter_type
      offset = function.params.first?.try(&.name) == "self" ? 1 : 0
      function.set_block_param_type(function.params[offset].id, TypeRef::INT32)
      raise "parameter-type mutation did not apply" unless function.params[offset].type == TypeRef::INT32
    when :parameter_default
      offset = function.params.first?.try(&.name) == "self" ? 1 : 0
      function.set_param_default_literal(offset, "false")
      raise "parameter-default mutation did not apply" unless function.params[offset].default_literal == "false"
    when :heap_block
      function.heap_block_param = true
      raise "heap-block mutation did not apply" unless function.heap_block_param
    when :definition
      original_definition = @function_defs[registry_name]?
      replacement = @function_defs.values.find do |candidate|
        original_definition && !candidate.same?(original_definition)
      end
      return false unless replacement
      @function_defs[registry_name] = replacement
      raise "definition replacement did not apply" if @function_defs[registry_name]?.try(&.same?(original_definition)) == true
    when :arena
      original_arena = @function_def_arenas[registry_name]?
      replacement_arena = Adamas::Compiler::Frontend::AstArena.new
      @function_def_arenas[registry_name] = replacement_arena
      raise "arena replacement did not apply" if @function_def_arenas[registry_name]?.try(&.same?(original_arena)) == true
    when :function
      original = function
      return false unless @module.remove_function(target)
      replacement = @module.create_function(target, original.return_type)
      original.params.each do |param|
        replacement.add_param(param.name, param.type, param.is_block)
      end
      raise "replacement Function unexpectedly reused the old identity" if replacement.same?(original)
      raise "replacement Function changed parameter types" unless replacement.params.map(&.type) == original_param_types
      raise "replacement Function changed parameter names" unless replacement.params.map(&.name) == original_param_names
    else
      return false
    end

    !active_force_lower_body_owns_callsite?(target, _ordinary)
  end

  def __test_crossed_fact_type_rejected?(target : String) : Bool
    retained, function, _registry_name, _ordinary, _capture = __test_install_active_body_owner(target)
    return false unless retained
    offset = function.params.first?.try(&.name) == "self" ? 1 : 0
    formal_types = function.params.skip(offset).map(&.type)
    return false if formal_types.empty?

    crossed_type = type_ref_for_name("RecursiveBodyConcreteStream")
    return false if crossed_type == formal_types[0]
    facts = [] of SourceCallArgument?
    formal_types.each { |type| facts << SourceCallArgument.new(type, false) }
    facts[0] = SourceCallArgument.new(crossed_type, false)
    crossed = CallsiteArgs.new(
      formal_types, nil, nil, false, false, nil, nil, facts, nil,
    )
    !active_force_lower_body_owns_callsite?(target, crossed)
  end

  def __test_false_literals_accept_partial_source_facts?(target : String) : Bool
    retained, function, _registry_name, _ordinary, _capture = __test_install_active_body_owner(target)
    return false unless retained
    offset = function.params.first?.try(&.name) == "self" ? 1 : 0
    formal_types = function.params.skip(offset).map(&.type)
    return false if formal_types.size < 2

    facts = [] of SourceCallArgument?
    formal_types.each_with_index do |type, index|
      facts << (index == 0 ? nil : SourceCallArgument.new(type, false))
    end
    callsite = CallsiteArgs.new(
      formal_types, Array.new(formal_types.size, false), nil, false, false, nil, nil, facts, nil,
    )
    active_force_lower_body_owns_callsite?(target, callsite)
  end

  def __test_active_body_source_binding_rejected?(target : String, inherited_alias : Bool, callback : Bool) : Bool
    retained, _function, registry_name, ordinary, capture = __test_install_active_body_owner(target)
    return false unless retained
    replay = capture.binding.not_nil!
    source_def = replay.source_def
    source_arena = replay.source_arena
    source = if inherited_alias
               ForceLowerExactSourceBinding.new(
                 source_def, source_arena, registry_name, true, target, source_def, source_arena,
               )
             else
               ForceLowerExactSourceBinding.new(source_def, source_arena, registry_name)
             end
    callback_source = if callback
                        RawCallbackSourceBinding.new(source_def, source_arena, ordinary)
                      else
                        nil
                      end
    capture.binding = ForceLowerReplayCallsite.new(
      source_def, source_arena, ordinary, {} of String => String, nil, registry_name,
      nil, callback_source, source,
    )
    !active_force_lower_source_current?(target, capture.binding.not_nil!)
  end

  def __test_recursive_result_dependencies(target : String, current_body : Bool = true) : Set(String)
    retained, function, registry_name, _ordinary, capture = __test_install_active_body_owner(target)
    retained.should be_true
    replay = capture.binding.not_nil!
    source_def = replay.source_def
    source_arena = replay.source_arena
    child = "#{target}#pending-child"
    dependencies = Set(String).new
    dependencies << child
    @force_lower_provisional_dependencies[target] = dependencies
    capture.active_body = nil unless current_body
    ctx = LoweringContext.new(function, @module, source_arena)

    record_force_lower_result_dependency(
      ctx, target, source_def, 0, source_def, source_arena, registry_name,
    )

    dependencies
  end
end

private def recursive_exact_body_replay_converter : {Adamas::HIR::AstToHir, String}
  source = <<-CRYSTAL
    class RecursiveBodyBaseStream
      def flush
        nil
      end
    end

    class RecursiveBodyConcreteStream < RecursiveBodyBaseStream
    end

    class RecursiveBodyNode
      def emit(io : RecursiveBodyBaseStream, again : Bool) : Nil
        if again
          emit(io, false)
          RecursiveBodyNestedCaller.new.dispatch(self, io)
        end
        io.flush
      end
    end

    abstract class RecursiveBodyValue
    end

    class RecursiveBodyPresent < RecursiveBodyValue
    end

    class RecursiveBodyLookup
      def lookup(again : Bool) : RecursiveBodyValue?
        return lookup(false) if again
        RecursiveBodyPresent.new
      end

      def lookup_defaulted(again : Bool = true) : RecursiveBodyValue?
        return lookup_defaulted(false) if again
        RecursiveBodyPresent.new
      end
    end

    class RecursiveBodyChildNode < RecursiveBodyNode
    end

    class RecursiveBodyNestedCaller
      def dispatch(node : RecursiveBodyNode, io : RecursiveBodyBaseStream) : Nil
        node.emit(io, false)
      end
    end

    class RecursiveBodyStarter
      def start(node : RecursiveBodyNode) : Nil
        node.emit(RecursiveBodyConcreteStream.new, true)
      end
    end

    RecursiveBodyStarter.new.start(RecursiveBodyChildNode.new)
    RecursiveBodyLookup.new.lookup(true)
    RecursiveBodyLookup.new.lookup_defaulted
    CRYSTAL

  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
  )
  converter.no_prelude = true
  main = [] of UInt64
  program.roots.each do |id|
    case node = arena[id]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
    else
      main << id.index.to_u64
    end
  end
  converter.lower_main(main)
  converter.spec_finish_parsed_lowering
  target = converter.spec_recursive_replay_target(
    "RecursiveBodyNode#emit",
    [converter.spec_type_ref_for_recursive_replay("RecursiveBodyBaseStream"), Adamas::HIR::TypeRef::BOOL],
  )
  {converter, target}
end

class Adamas::HIR::AstToHir
  def spec_type_ref_for_recursive_replay(name : String) : TypeRef
    type_ref_for_name(name)
  end

  def spec_recursive_replay_target(base : String, args : Array(TypeRef)) : String
    mangle_function_name(base, args)
  end

  def spec_finish_parsed_lowering : Nil
    process_pending_lower_functions
    lower_missing_call_targets
    process_pending_lower_functions
  end
end

describe "active exact-body callsite ownership" do
  it "coalesces only proven ordinary inputs and retains family discovery" do
    converter, target = recursive_exact_body_replay_converter
    observation = converter.__test_active_body_owner_observation(target)

    observation.retained.should be_true
    observation.exact_call_owned.should be_true
    observation.source_facts_owned.should be_true
    observation.missing_kind_rejected.should be_true
    observation.literal_rejected.should be_true
    observation.block_rejected.should be_true
    observation.named_rejected.should be_true
    observation.callback_rejected.should be_true
    observation.other_target_rejected.should be_true
    observation.exact_pending_preserved.should be_true
    observation.family_discovery_recorded.should be_true
  end

  it "rejects stale source and mutated ABI receipts" do
    [:return_type, :parameter_type, :parameter_default, :heap_block, :definition, :arena, :function].each do |mutation|
      converter, target = recursive_exact_body_replay_converter
      raise "active body receipt accepted #{mutation} mutation" unless
        converter.__test_active_body_mutation_rejected?(target, mutation)
    end
  end

  it "rejects crossed fact types but accepts complete false literals with missing fact slots" do
    converter, target = recursive_exact_body_replay_converter
    converter.__test_crossed_fact_type_rejected?(target).should be_true

    converter, target = recursive_exact_body_replay_converter
    converter.__test_false_literals_accept_partial_source_facts?(target).should be_true
  end

  it "rejects inherited aliases and callback-owned replay sources" do
    converter, target = recursive_exact_body_replay_converter
    converter.__test_active_body_source_binding_rejected?(target, inherited_alias: true, callback: false).should be_true

    converter, target = recursive_exact_body_replay_converter
    converter.__test_active_body_source_binding_rejected?(target, inherited_alias: false, callback: true).should be_true
  end

  it "keeps an unsettled child of an active Nil-returning body" do
    converter, target = recursive_exact_body_replay_converter
    converter.__test_recursive_result_dependencies(target).should eq(Set{"#{target}#pending-child"})
  end

  it "keeps an unsettled child of an active body with a nullable abstract result" do
    converter, _ = recursive_exact_body_replay_converter
    target = converter.spec_recursive_replay_target("RecursiveBodyLookup#lookup", [Adamas::HIR::TypeRef::BOOL])
    converter.__test_recursive_result_dependencies(target).should eq(Set{"#{target}#pending-child"})
  end

  it "keeps only the distinct child of an active body with default parameters" do
    converter, _ = recursive_exact_body_replay_converter
    target = converter.spec_recursive_replay_target("RecursiveBodyLookup#lookup_defaulted", [Adamas::HIR::TypeRef::BOOL])
    converter.__test_recursive_result_dependencies(target).should eq(Set{"#{target}#pending-child"})

    converter, _ = recursive_exact_body_replay_converter
    target = converter.spec_recursive_replay_target("RecursiveBodyLookup#lookup_defaulted", [Adamas::HIR::TypeRef::BOOL])
    converter.__test_recursive_result_dependencies(target, current_body: false).should eq(Set{target, "#{target}#pending-child"})
  end

  it "keeps the self dependency when the active body has no current witness" do
    converter, _ = recursive_exact_body_replay_converter
    target = converter.spec_recursive_replay_target("RecursiveBodyLookup#lookup", [Adamas::HIR::TypeRef::BOOL])
    converter.__test_recursive_result_dependencies(target, current_body: false).should eq(Set{target, "#{target}#pending-child"})
  end
end
