require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_materialize_queue_function(name : String) : Nil
    lower_function_if_needed(name)
    @module.has_function_with_body?(name).should be_true
    @function_defs.has_key?(name).should be_true
    @function_def_arenas.has_key?(name).should be_true
  end

  def __test_seed_queue_retry(
    name : String,
    dependencies : Array(String),
    requires_result : Bool = true,
  ) : ForceLowerRetryRequest
    source_def = @function_defs[name]? || raise "missing real source Def for #{name}"
    source_arena = @function_def_arenas[name]? || raise "missing real source arena for #{name}"
    function = @module.function_by_name(name) || raise "missing lowered body for #{name}"

    exact_source = ForceLowerExactSourceBinding.new(source_def, source_arena, name)
    force_lower_exact_source_matches?(name, exact_source).should be_true

    callsite = CallsiteArgs.new(
      [] of TypeRef,
      nil,
      nil,
      false,
      false,
      nil,
      name,
      nil,
      nil,
    )
    @pending_arg_types[name] = callsite
    replay = ForceLowerReplayCallsite.new(
      source_def,
      source_arena,
      copy_force_lower_callsite(callsite),
      @type_param_map.dup,
      @current_namespace_override,
      name,
    )

    # Preserve the actual source body and registry entry, but model the exact
    # completed-yet-provisional HIR state that the retry queue repairs.
    @function_types[name] = TypeRef::VOID
    function.return_type = TypeRef::VOID
    set_function_state(name, FunctionLoweringState::Completed)
    if dependencies.empty?
      @force_lower_provisional_dependencies.delete(name)
    else
      @force_lower_provisional_dependencies[name] = dependencies.to_set
    end
    ForceLowerRetryRequest.new(name, dependencies.dup, false, replay, exact_source, requires_result)
  end

  def __test_force_lower_exact_source_binding(
    name : String,
    selected_registry_name : String? = nil,
    source_name : String? = nil,
    foreign_arena : Bool = false,
  ) : ForceLowerExactSourceBinding?
    selected_name = source_name || name
    source_def = @function_defs[selected_name]?
    source_arena = if foreign_arena
                     __test_foreign_source_arena
                   else
                     @function_def_arenas[selected_name]?
                   end
    force_lower_exact_source_binding(name, source_def, source_def, source_arena, selected_registry_name)
  end

  def __test_register_source_alias(name : String, source_name : String) : Nil
    @function_defs[name] = @function_defs[source_name]
    @function_def_arenas[name] = @function_def_arenas[source_name]
  end

  def __test_lower_and_capture_replay(
    name : String,
    callsite : CallsiteArgs,
    exact_source : ForceLowerExactSourceBinding? = nil,
  ) : ForceLowerReplayCallsite?
    @pending_arg_types[name] = callsite
    @force_lower_replay_source_bindings[name] = exact_source if exact_source
    capture = ForceLowerReplayCapture.new(name, @force_lower_current_replay_capture)
    prior_capture = @force_lower_active_replay_captures[name]?
    prior_current_capture = @force_lower_current_replay_capture
    @force_lower_active_replay_captures[name] = capture
    @force_lower_current_replay_capture = capture
    begin
      lower_function_if_needed_impl(name, __LINE__, capture)
    ensure
      @force_lower_current_replay_capture = prior_current_capture
      if prior_capture
        @force_lower_active_replay_captures[name] = prior_capture.not_nil!
      else
        @force_lower_active_replay_captures.delete(name)
      end
    end
    capture.binding
  end

  def __test_empty_callsite : CallsiteArgs
    CallsiteArgs.new([] of TypeRef, nil, nil)
  end

  def __test_stale_queue_request(request : ForceLowerRetryRequest, foreign_name : String) : ForceLowerRetryRequest
    foreign_def = @function_defs[foreign_name]
    foreign_arena = @function_def_arenas[foreign_name]
    stale = ForceLowerExactSourceBinding.new(foreign_def, foreign_arena, request.name)
    force_lower_exact_source_matches?(request.name, stale).should be_false
    ForceLowerRetryRequest.new(request.name, request.refused, request.bypass_inline_yield,
      request.replay_callsite, stale, request.requires_result)
  end

  def __test_run_seeded_retry_queue(
    prequeued : Array(ForceLowerRetryRequest),
    initial : ForceLowerRetryRequest,
  ) : Bool
    @force_lower_retry_work.clear
    prequeued.each { |request| @force_lower_retry_work << request }
    begin
      run_force_lower_retry_driver(initial)
    rescue pending : ExactResultPending
      false
    end
  end

  def __test_provisional_retry?(name : String) : Bool
    @force_lower_provisional_dependencies.has_key?(name)
  end

  def __test_function_result_settled?(name : String, requires_result : Bool) : Bool
    settled_force_lower_demand?(name, requires_result)
  end

  def __test_function_result_type(name : String) : TypeRef
    @module.function_by_name(name).not_nil!.return_type
  end

  def __test_callback_abi(
    param_types : Array(TypeRef),
    return_type : TypeRef,
    proc_type : TypeRef,
    self_source_name : String? = nil,
    self_source_foreign_arena : Bool = false,
    wildcard : Bool = false,
  ) : RawCallbackAbi
    source_def = self_source_name.try { |name| @function_defs[name]? }
    source_arena = if self_source_name
                     self_source_foreign_arena ? __test_foreign_source_arena : @function_def_arenas[self_source_name.not_nil!]
                   end
    RawCallbackAbi.new(param_types, return_type, proc_type, source_def, source_arena, wildcard)
  end

  def __test_callback_proc_type(param_types : Array(TypeRef), return_type : TypeRef) : TypeRef
    @module.intern_type(TypeDescriptor.new(TypeKind::Proc, "Proc", param_types + [return_type]))
  end

  def __test_callback_abi_matches?(expected : RawCallbackAbi, actual : RawCallbackAbi) : Bool
    initializer_callback_abi_matches?(expected, actual)
  end

  def __test_seed_callback_replay(
    name : String,
    abi : RawCallbackAbi,
    callsite : CallsiteArgs,
  ) : ForceLowerReplayCallsite
    source_def = @function_defs[name]? || raise "missing source Def for #{name}"
    source_arena = @function_def_arenas[name]? || raise "missing source arena for #{name}"
    @raw_callback_abis[name] = abi
    callback_source = RawCallbackSourceBinding.new(source_def, source_arena, callsite)
    @raw_callback_source_bindings[name] = callback_source
    ForceLowerReplayCallsite.new(
      source_def, source_arena, copy_force_lower_callsite(callsite), @type_param_map.dup,
      @current_namespace_override, name, copy_initializer_callback_abi(abi),
      copy_initializer_callback_source(callback_source),
    )
  end

  def __test_raw_callback_source(
    name : String,
    callsite : CallsiteArgs,
    actual_source_name : String? = nil,
    actual_foreign_arena : Bool = false,
  ) : RawCallbackSourceBinding
    selected_name = actual_source_name || name
    source_def = @function_defs[selected_name]? || raise "missing source Def for #{selected_name}"
    source_arena = if actual_foreign_arena
                     __test_foreign_source_arena
                   else
                     @function_def_arenas[selected_name]? || raise "missing source arena for #{selected_name}"
                   end
    RawCallbackSourceBinding.new(source_def, source_arena, callsite)
  end

  def __test_replay_callsite_current?(name : String, replay : ForceLowerReplayCallsite) : Bool
    force_lower_replay_callsite_current?(name, replay)
  end

  def __test_replace_callback_abi(name : String, abi : RawCallbackAbi) : Nil
    @raw_callback_abis[name] = abi
  end

  def __test_replace_callback_source(name : String, source : RawCallbackSourceBinding) : Nil
    @raw_callback_source_bindings[name] = source
  end

  def __test_mutate_callback_callsite(callsite : CallsiteArgs) : Nil
    callsite.types[0] = TypeRef::NIL
    callsite.literals.not_nil![0] = true
    callsite.source_argument_facts.not_nil![0] = SourceCallArgument.new(TypeRef::NIL, false)
  end

  def __test_replay_callback_source_binding(replay : ForceLowerReplayCallsite) : SourceCallBinding?
    replay.callback_source.try(&.callsite.source_binding)
  end

  def __test_replay_callsite_type(replay : ForceLowerReplayCallsite) : TypeRef
    replay.callback_source.not_nil!.callsite.types[0]
  end

  def __test_replay_callsite_source_fact_type(replay : ForceLowerReplayCallsite) : TypeRef
    replay.callback_source.not_nil!.callsite.source_argument_facts.not_nil![0].not_nil!.type_ref
  end

  def __test_replay_callsite_literal(replay : ForceLowerReplayCallsite) : Bool
    replay.callback_source.not_nil!.callsite.literals.not_nil![0]
  end

  def __test_callback_callsite(
    name : String,
    types : Array(TypeRef) = [TypeRef::INT32],
    literals : Array(Bool)? = [false],
    enum_names : Array(String?)? = [nil] of String?,
    has_block : Bool = true,
    has_named_args : Bool = true,
    named_arg_names : Array(String)? = ["value"],
    source_fact_type : TypeRef = TypeRef::INT32,
    source_binding : SourceCallBinding? = nil,
  ) : CallsiteArgs
    source_facts = [SourceCallArgument.new(source_fact_type, false)] of SourceCallArgument?
    CallsiteArgs.new(
      types, literals, enum_names, has_block, has_named_args, named_arg_names,
      name, source_facts, source_binding,
    )
  end

  def __test_source_binding(name : String) : SourceCallBinding
    source_def = @function_defs[name]? || raise "missing source Def for #{name}"
    source_arena = @function_def_arenas[name]? || raise "missing source arena for #{name}"
    supplied = [SourceCallArgument.new(TypeRef::INT32, false)] of SourceCallArgument?
    defaulted = [SourceCallArgument.new(TypeRef::NIL, false)] of SourceCallArgument?
    SourceCallBinding.new(
      name, source_def, source_arena, supplied, name,
      SourceCallArgument.new(TypeRef::INT32, false), defaulted,
    )
  end

  def __test_change_source_binding_supplied(binding : SourceCallBinding, type_ref : TypeRef) : Nil
    binding.supplied_types[0] = SourceCallArgument.new(type_ref, false)
  end

  def __test_nested_source_binding(name : String) : SourceCallBinding
    source_def = @function_defs[name]? || raise "missing source Def for #{name}"
    source_arena = @function_def_arenas[name]? || raise "missing source arena for #{name}"
    nested = [SourceCallArgument.new(TypeRef::INT32, false)] of SourceCallArgument
    facts = [{TypeRef::INT32, false}]
    supplied = [SourceCallArgument.new(TypeRef::INT32, false, nested, facts)] of SourceCallArgument?
    defaulted = [SourceCallArgument.new(TypeRef::NIL, false)] of SourceCallArgument?
    SourceCallBinding.new(
      name, source_def, source_arena, supplied, name,
      SourceCallArgument.new(TypeRef::INT32, false), defaulted,
    )
  end

  def __test_mutate_nested_source_binding(binding : SourceCallBinding) : Nil
    fact = binding.supplied_types[0].not_nil!
    fact.rest_values.not_nil![0] = SourceCallArgument.new(TypeRef::NIL, false)
    fact.value_facts.not_nil![0] = {TypeRef::NIL, false}
    binding.supplied_types[0] = SourceCallArgument.new(TypeRef::NIL, false)
    binding.defaulted_types[0] = SourceCallArgument.new(TypeRef::INT32, false)
  end

  def __test_binding_source_type(binding : SourceCallBinding, defaulted : Bool = false) : TypeRef
    values = defaulted ? binding.defaulted_types : binding.supplied_types
    values[0].not_nil!.type_ref
  end

  def __test_binding_nested_type(binding : SourceCallBinding) : TypeRef
    binding.supplied_types[0].not_nil!.rest_values.not_nil![0].not_nil!.type_ref
  end

  def __test_binding_nested_value_fact_type(binding : SourceCallBinding) : TypeRef
    binding.supplied_types[0].not_nil!.value_facts.not_nil![0][0]
  end

  def __test_binding_block_result_type(binding : SourceCallBinding) : TypeRef
    binding.block_result.not_nil!.type_ref
  end

  def __test_callback_source_matches?(
    name : String,
    expected_callsite : CallsiteArgs,
    actual_callsite : CallsiteArgs,
    actual_source_name : String? = nil,
    actual_foreign_arena : Bool = false,
  ) : Bool
    expected_def = @function_defs[name]? || raise "missing source Def for #{name}"
    expected_arena = @function_def_arenas[name]? || raise "missing source arena for #{name}"
    actual_name = actual_source_name || name
    actual_def = @function_defs[actual_name]? || raise "missing source Def for #{actual_name}"
    actual_arena = actual_foreign_arena ? __test_foreign_source_arena : (@function_def_arenas[actual_name]? || raise "missing source arena for #{actual_name}")
    expected = RawCallbackSourceBinding.new(expected_def, expected_arena, expected_callsite)
    actual = RawCallbackSourceBinding.new(actual_def, actual_arena, actual_callsite)
    initializer_callback_source_matches?(expected, actual)
  end

  def __test_foreign_source_arena : Adamas::Compiler::Frontend::ArenaLike
    source = "def foreign_queue_source; 1; end"
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    parser.parse_program.arena
  end

  def __test_copy_callback_source(name : String, callsite : CallsiteArgs) : RawCallbackSourceBinding?
    source_def = @function_defs[name]? || raise "missing source Def for #{name}"
    source_arena = @function_def_arenas[name]? || raise "missing source arena for #{name}"
    copy_initializer_callback_source(RawCallbackSourceBinding.new(source_def, source_arena, callsite))
  end

  def __test_callback_source_binding(source : RawCallbackSourceBinding) : SourceCallBinding?
    source.callsite.source_binding
  end

  def __test_copy_source_binding(callsite : CallsiteArgs) : SourceCallBinding?
    copy_force_lower_callsite(callsite).source_binding
  end

  def __test_queue_has_producer?(name : String, requires_result : Bool) : Bool
    force_lower_retry_has_queued_producer?(name, requires_result)
  end

  def __test_queue_retry(request : ForceLowerRetryRequest) : Nil
    @force_lower_retry_work.clear
    @force_lower_retry_work << request
  end
end

private def force_lower_dependency_queue_fixture : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    def retry_queue_leaf : Int32
      65
    end

    def retry_queue_shared
      retry_queue_leaf
    end

    def retry_queue_ancestor_a
      retry_queue_shared
    end

    def retry_queue_ancestor_b
      retry_queue_shared
    end

    def retry_queue_cycle_left
      retry_queue_cycle_right
    end

    def retry_queue_cycle_right
      retry_queue_cycle_left
    end

    def retry_queue_independent
      retry_queue_leaf
    end

    def retry_queue_body_only
      65
    end
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "/tmp/force_lower_dependency_queue_spec.cr"},
  )
  converter.no_prelude = true
  program.roots.each do |id|
    node = arena[id]
    converter.register_function(node) if node.is_a?(Adamas::Compiler::Frontend::DefNode)
  end
  %w(
    retry_queue_leaf
    retry_queue_shared
    retry_queue_ancestor_a
    retry_queue_ancestor_b
    retry_queue_cycle_left
    retry_queue_cycle_right
    retry_queue_body_only
    retry_queue_independent
  ).each do |name|
    converter.__test_materialize_queue_function(name)
  end
  converter
end

private def force_lower_registry_capture_fixture(name : String) : Adamas::HIR::AstToHir
  source = "def #{name} : Int32\n  65\nend\n"
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "/tmp/force_lower_registry_capture_spec.cr"},
  )
  converter.no_prelude = true
  program.roots.each do |id|
    node = arena[id]
    converter.register_function(node) if node.is_a?(Adamas::Compiler::Frontend::DefNode)
  end
  converter
end

describe "dependency-aware exact source retry scheduling" do
  it "uses the physical registry key for ordinary replay capture" do
    ordinary = force_lower_registry_capture_fixture("registry_capture_target")
    ordinary_replay = ordinary.__test_lower_and_capture_replay(
      "registry_capture_target", ordinary.__test_empty_callsite,
    )
    ordinary_replay.should_not be_nil
    ordinary_replay.not_nil!.source_registry_name.should eq("registry_capture_target")
  end

  it "preserves the lexical registry key for an aliased replay capture" do
    alias_converter = force_lower_registry_capture_fixture("registry_capture_source")
    alias_converter.__test_register_source_alias("registry_capture_lexical", "registry_capture_source")
    alias_source = alias_converter.__test_force_lower_exact_source_binding(
      "registry_capture_source", selected_registry_name: "registry_capture_lexical",
      source_name: "registry_capture_source",
    )
    alias_source.should_not be_nil
    alias_source.not_nil!.source_registry_name.should eq("registry_capture_lexical")
    alias_replay = alias_converter.__test_lower_and_capture_replay(
      "registry_capture_source", alias_converter.__test_empty_callsite,
      alias_source.not_nil!,
    )
    alias_replay.should_not be_nil
    alias_replay.not_nil!.source_registry_name.should eq("registry_capture_lexical")
  end

  it "retains the registered source name when the exact source is selected by its physical name" do
    converter = force_lower_dependency_queue_fixture

    exact = converter.__test_force_lower_exact_source_binding("retry_queue_shared")
    exact.should_not be_nil
    exact.not_nil!.source_registry_name.should eq("retry_queue_shared")
  end

  it "rejects mismatched registry names, foreign arenas, and foreign Defs" do
    converter = force_lower_dependency_queue_fixture

    converter.__test_force_lower_exact_source_binding(
      "retry_queue_shared", selected_registry_name: "retry_queue_leaf",
    ).should be_nil
    converter.__test_force_lower_exact_source_binding(
      "retry_queue_shared", foreign_arena: true,
    ).should be_nil
    converter.__test_force_lower_exact_source_binding(
      "retry_queue_shared", source_name: "retry_queue_leaf",
    ).should be_nil
  end

  it "settles a shared producer before either queued ancestor consumes it" do
    converter = force_lower_dependency_queue_fixture
    shared = converter.__test_seed_queue_retry("retry_queue_shared", ["retry_queue_leaf"])
    ancestor_b = converter.__test_seed_queue_retry("retry_queue_ancestor_b", ["retry_queue_shared"])
    ancestor_a = converter.__test_seed_queue_retry("retry_queue_ancestor_a", ["retry_queue_shared"])

    # The shared producer is already queued below an ancestor when the active
    # ancestor resumes. A LIFO-only drain can consume/drop the ancestor first.
    converter.__test_run_seeded_retry_queue([shared, ancestor_b], ancestor_a).should be_true

    %w(retry_queue_shared retry_queue_ancestor_a retry_queue_ancestor_b).each do |name|
      converter.__test_provisional_retry?(name).should be_false
      converter.__test_function_result_type(name).should_not eq(Adamas::HIR::TypeRef::VOID)
    end
  end

  it "does not report an unresolved initial demand after independent work settles" do
    converter = force_lower_dependency_queue_fixture
    consumer = converter.__test_seed_queue_retry("retry_queue_ancestor_a", [] of String)
    consumer.refused << "retry_queue_shared"
    producer = converter.__test_seed_queue_retry("retry_queue_shared", ["retry_queue_ancestor_a"])
    stale_producer = converter.__test_stale_queue_request(producer, "retry_queue_body_only")
    independent = converter.__test_seed_queue_retry("retry_queue_independent", ["retry_queue_leaf"])

    # Name-only ordering sees a cycle through the stale request. Unrelated
    # progress must not certify this initial consumer's unresolved result.
    converter.__test_run_seeded_retry_queue([stale_producer, independent], consumer).should be_false
    converter.__test_function_result_type("retry_queue_ancestor_a").should eq(Adamas::HIR::TypeRef::VOID)
    converter.__test_function_result_type("retry_queue_independent").should eq(Adamas::HIR::TypeRef::INT32)
  end

  it "terminates a cyclic exact dependency graph without claiming settlement" do
    converter = force_lower_dependency_queue_fixture
    left = converter.__test_seed_queue_retry("retry_queue_cycle_left", ["retry_queue_cycle_right"])
    right = converter.__test_seed_queue_retry("retry_queue_cycle_right", ["retry_queue_cycle_left"])

    converter.__test_run_seeded_retry_queue([left], right).should be_false
    converter.__test_provisional_retry?("retry_queue_cycle_left").should be_true
    converter.__test_provisional_retry?("retry_queue_cycle_right").should be_true
  end

  it "accepts a completed Void body for body demand but not for result demand" do
    converter = force_lower_dependency_queue_fixture
    body = converter.__test_seed_queue_retry("retry_queue_body_only", [] of String, requires_result: false)
    converter.__test_function_result_type("retry_queue_body_only").should eq(Adamas::HIR::TypeRef::VOID)
    converter.__test_function_result_settled?("retry_queue_body_only", false).should be_true
    converter.__test_function_result_settled?("retry_queue_body_only", true).should be_false
    body.requires_result.should be_false
  end

  it "does not let a queued body-only request satisfy a result dependency" do
    converter = force_lower_dependency_queue_fixture
    body = converter.__test_seed_queue_retry("retry_queue_body_only", [] of String, requires_result: false)
    converter.__test_queue_retry(body)

    converter.__test_queue_has_producer?("retry_queue_body_only", false).should be_true
    converter.__test_queue_has_producer?("retry_queue_body_only", true).should be_false
    converter.__test_function_result_settled?("retry_queue_body_only", false).should be_true
    converter.__test_function_result_settled?("retry_queue_body_only", true).should be_false
  end

  it "rejects replay receipts when raw callback ABI facts change" do
    converter = force_lower_dependency_queue_fixture
    source_name = "retry_queue_shared"

    int_proc = converter.__test_callback_proc_type([Adamas::HIR::TypeRef::INT32], Adamas::HIR::TypeRef::INT32)
    nil_proc = converter.__test_callback_proc_type([Adamas::HIR::TypeRef::NIL], Adamas::HIR::TypeRef::INT32)
    int_nil_proc = converter.__test_callback_proc_type([Adamas::HIR::TypeRef::INT32], Adamas::HIR::TypeRef::NIL)
    base = converter.__test_callback_abi(
      [Adamas::HIR::TypeRef::INT32], Adamas::HIR::TypeRef::INT32, int_proc,
      self_source_name: source_name,
    )
    converter.__test_callback_abi_matches?(base, converter.__test_callback_abi(
      [Adamas::HIR::TypeRef::NIL], Adamas::HIR::TypeRef::INT32, nil_proc,
      self_source_name: source_name,
    )).should be_false
    converter.__test_callback_abi_matches?(base, converter.__test_callback_abi(
      [Adamas::HIR::TypeRef::INT32], Adamas::HIR::TypeRef::NIL, int_proc,
      self_source_name: source_name,
    )).should be_false
    converter.__test_callback_abi_matches?(base, converter.__test_callback_abi(
      [Adamas::HIR::TypeRef::INT32], Adamas::HIR::TypeRef::INT32, nil_proc,
      self_source_name: source_name,
    )).should be_false
    converter.__test_callback_abi_matches?(base, converter.__test_callback_abi(
      [Adamas::HIR::TypeRef::INT32], Adamas::HIR::TypeRef::INT32, int_nil_proc,
      self_source_name: source_name,
    )).should be_false
    converter.__test_callback_abi_matches?(base, converter.__test_callback_abi(
      [Adamas::HIR::TypeRef::INT32], Adamas::HIR::TypeRef::INT32, int_proc,
      self_source_name: "retry_queue_independent",
    )).should be_false
    converter.__test_callback_abi_matches?(base, converter.__test_callback_abi(
      [Adamas::HIR::TypeRef::INT32], Adamas::HIR::TypeRef::INT32, int_proc,
      self_source_name: source_name, self_source_foreign_arena: true,
    )).should be_false

    # The ABI wildcard is ownership-relevant even when the current shape is
    # otherwise identical: it changes how callback formals are instantiated.
    converter.__test_callback_abi_matches?(base, converter.__test_callback_abi(
      [Adamas::HIR::TypeRef::INT32], Adamas::HIR::TypeRef::INT32, int_proc,
      self_source_name: source_name, wildcard: true,
    )).should be_false

    callsite = converter.__test_callback_callsite(source_name)
    replay = converter.__test_seed_callback_replay(source_name, base, callsite)
    converter.__test_replay_callsite_current?(source_name, replay).should be_true
    converter.__test_replace_callback_abi(source_name, converter.__test_callback_abi(
      [Adamas::HIR::TypeRef::NIL], Adamas::HIR::TypeRef::INT32, nil_proc,
      self_source_name: source_name,
    ))
    converter.__test_replay_callsite_current?(source_name, replay).should be_false
    converter.__test_replace_callback_abi(source_name, converter.__test_callback_abi(
      [Adamas::HIR::TypeRef::INT32], Adamas::HIR::TypeRef::NIL, int_proc,
      self_source_name: source_name,
    ))
    converter.__test_replay_callsite_current?(source_name, replay).should be_false
    converter.__test_replace_callback_abi(source_name, converter.__test_callback_abi(
      [Adamas::HIR::TypeRef::INT32], Adamas::HIR::TypeRef::INT32, int_proc,
      self_source_name: "retry_queue_independent",
    ))
    converter.__test_replay_callsite_current?(source_name, replay).should be_false
    converter.__test_replace_callback_abi(source_name, converter.__test_callback_abi(
      [Adamas::HIR::TypeRef::INT32], Adamas::HIR::TypeRef::INT32, int_proc,
      self_source_name: source_name, self_source_foreign_arena: true,
    ))
    converter.__test_replay_callsite_current?(source_name, replay).should be_false
    converter.__test_replace_callback_abi(source_name, converter.__test_callback_abi(
      [Adamas::HIR::TypeRef::INT32], Adamas::HIR::TypeRef::INT32, int_proc,
      self_source_name: source_name, wildcard: true,
    ))
    converter.__test_replay_callsite_current?(source_name, replay).should be_false
  end

  it "rejects callback source Def, arena, and callshape changes" do
    converter = force_lower_dependency_queue_fixture
    source_name = "retry_queue_shared"
    original = converter.__test_callback_callsite(source_name)

    converter.__test_callback_source_matches?(source_name, original, original).should be_true
    converter.__test_callback_source_matches?(
      source_name, original, original, actual_source_name: "retry_queue_independent",
    ).should be_false
    converter.__test_callback_source_matches?(
      source_name, original, original, actual_foreign_arena: true,
    ).should be_false

    converter.__test_callback_source_matches?(source_name, original,
      converter.__test_callback_callsite(source_name, types: [Adamas::HIR::TypeRef::NIL])).should be_false
    converter.__test_callback_source_matches?(source_name, original,
      converter.__test_callback_callsite(source_name, literals: [true])).should be_false
    converter.__test_callback_source_matches?(source_name, original,
      converter.__test_callback_callsite(source_name, enum_names: ["QueueKind"] of String?)).should be_false
    converter.__test_callback_source_matches?(source_name, original,
      converter.__test_callback_callsite(source_name, has_block: false)).should be_false
    converter.__test_callback_source_matches?(source_name, original,
      converter.__test_callback_callsite(source_name, has_named_args: false)).should be_false
    converter.__test_callback_source_matches?(source_name, original,
      converter.__test_callback_callsite(source_name, named_arg_names: ["other"])).should be_false
    converter.__test_callback_source_matches?(source_name, original,
      converter.__test_callback_callsite("retry_queue_independent")).should be_false
    converter.__test_callback_source_matches?(source_name, original,
      converter.__test_callback_callsite(source_name, source_fact_type: Adamas::HIR::TypeRef::NIL)).should be_false

    int_proc = converter.__test_callback_proc_type([Adamas::HIR::TypeRef::INT32], Adamas::HIR::TypeRef::INT32)
    abi = converter.__test_callback_abi(
      [Adamas::HIR::TypeRef::INT32], Adamas::HIR::TypeRef::INT32, int_proc,
      self_source_name: source_name,
    )
    replay = converter.__test_seed_callback_replay(source_name, abi, original)
    converter.__test_replay_callsite_current?(source_name, replay).should be_true
    converter.__test_replace_callback_source(source_name, converter.__test_raw_callback_source(
      source_name, original, actual_source_name: "retry_queue_independent",
    ))
    expect_raises(Adamas::HIR::LoweringError, "raw callback source binding changed for #{source_name}") do
      converter.__test_replay_callsite_current?(source_name, replay)
    end
    converter.__test_replace_callback_source(source_name, converter.__test_raw_callback_source(
      source_name, original, actual_foreign_arena: true,
    ))
    expect_raises(Adamas::HIR::LoweringError, "raw callback source binding changed for #{source_name}") do
      converter.__test_replay_callsite_current?(source_name, replay)
    end
    converter.__test_replace_callback_source(source_name, converter.__test_raw_callback_source(
      source_name, converter.__test_callback_callsite(source_name, types: [Adamas::HIR::TypeRef::NIL]),
    ))
    converter.__test_replay_callsite_current?(source_name, replay).should be_false

    changed_binding = converter.__test_source_binding("retry_queue_shared")
    converter.__test_change_source_binding_supplied(changed_binding, Adamas::HIR::TypeRef::NIL)
    changed = converter.__test_callback_callsite(source_name, source_binding: changed_binding)
    converter.__test_callback_source_matches?(source_name, original, changed).should be_false
  end

  it "snapshots mutable call-binding facts inside callback replay receipts" do
    converter = force_lower_dependency_queue_fixture
    source_name = "retry_queue_shared"
    original_binding = converter.__test_nested_source_binding(source_name)
    callsite = converter.__test_callback_callsite(source_name, source_binding: original_binding)
    int_proc = converter.__test_callback_proc_type([Adamas::HIR::TypeRef::INT32], Adamas::HIR::TypeRef::INT32)
    abi = converter.__test_callback_abi(
      [Adamas::HIR::TypeRef::INT32], Adamas::HIR::TypeRef::INT32, int_proc,
      self_source_name: source_name,
    )
    replay = converter.__test_seed_callback_replay(source_name, abi, callsite)
    converter.__test_replay_callsite_current?(source_name, replay).should be_true
    saved = converter.__test_copy_callback_source(source_name, callsite).not_nil!
    saved_binding = saved.callsite.source_binding.not_nil!

    # Mutate the call-binder vectors and nested source fact after the receipt
    # is captured. A replay snapshot must keep the original evidence values.
    converter.__test_mutate_nested_source_binding(original_binding)

    saved_binding.supplied_types[0].not_nil!.type_ref.should eq(Adamas::HIR::TypeRef::INT32)
    saved_binding.supplied_types[0].not_nil!.rest_values.not_nil![0].not_nil!.type_ref.should eq(Adamas::HIR::TypeRef::INT32)
    saved_binding.supplied_types[0].not_nil!.value_facts.not_nil![0][0].should eq(Adamas::HIR::TypeRef::INT32)
    saved_binding.defaulted_types[0].not_nil!.type_ref.should eq(Adamas::HIR::TypeRef::NIL)
    saved_binding.block_result.not_nil!.type_ref.should eq(Adamas::HIR::TypeRef::INT32)
    converter.__test_replay_callback_source_binding(replay).not_nil!.supplied_types[0].not_nil!.type_ref.should eq(Adamas::HIR::TypeRef::INT32)
    converter.__test_replay_callsite_type(replay).should eq(Adamas::HIR::TypeRef::INT32)
    converter.__test_replay_callsite_current?(source_name, replay).should be_false

    # The source callsite itself is also mutable: its raw registry entry must
    # not alias the callback source snapshot retained by the replay request.
    converter.__test_mutate_callback_callsite(callsite)
    converter.__test_replay_callsite_type(replay).should eq(Adamas::HIR::TypeRef::INT32)
    converter.__test_replay_callsite_source_fact_type(replay).should eq(Adamas::HIR::TypeRef::INT32)
    converter.__test_replay_callsite_literal(replay).should be_false
  end
end
