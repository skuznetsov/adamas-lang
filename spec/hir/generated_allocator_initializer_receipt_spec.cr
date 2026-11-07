require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_natural_initializer_receipt_name : String
    @generated_allocator_layout_recipes.each_value do |recipe|
      contract = recipe.initializer_call
      next unless contract
      name = contract.target_name
      source = @materialized_initializer_sources[name]?
      next unless source && source.owner == "NaturalInitializerReplayOwner" &&
                  source.source_name == name &&
                  contract.source.symbol_name == "NaturalInitializerReplayOwner#initialize$block" &&
                  contract.target.same?(source.function)
      return name
    end
    raise "natural captured-block receipt did not identify its materialized initializer source"
  end

  def __test_initializer_source(name : String)
    @materialized_initializer_sources[name]
  end

  def __test_generated_initializer_receipt(name : String)
    @generated_allocator_layout_recipes.each do |wrapper_name, recipe|
      contract = recipe.initializer_call
      next unless contract && contract.target_name == name

      wrapper = @module.function_by_name(wrapper_name)
      raise "generated allocator wrapper is missing: #{wrapper_name}" unless wrapper

      call = nil.as(Adamas::HIR::Call?)
      wrapper.blocks.each do |block|
        block.instructions.each do |instruction|
          next unless candidate = instruction.as?(Adamas::HIR::Call)
          call = candidate if candidate.id == contract.id
        end
      end
      raise "generated allocator initializer call is missing: #{wrapper_name}" unless call

      return {
        wrapper: wrapper,
        contract: contract,
        call:     call.not_nil!,
      }
    end
    raise "generated allocator initializer receipt is missing for #{name}"
  end

  def __test_prepare_no_return_transition(name : String, prior_is_noreturn : Bool)
    original = __test_initializer_source(name)
    receipt = __test_generated_initializer_receipt(name)
    old_function = receipt[:contract].target
    wrapper = receipt[:wrapper]
    call = receipt[:call]
    no_return = type_ref_for_name("NoReturn")

    prior = original
    if prior_is_noreturn
      # Build the wrapper's existing NoReturn generation explicitly. The
      # production renewal path does not rebuild allocator CFG, so a receipt
      # must not bless a transition away from this category either.
      old_function.return_type = no_return
      old_function.get_block(old_function.entry_block).terminator = Adamas::HIR::Unreachable.new
      prior = __test_copy_initializer_source(original, old_function, no_return, true)
      @materialized_initializer_sources[name] = prior

      replacement_call = Adamas::HIR::Call.with_receiver(
        call.id, no_return, call.receiver_value, call.method_name, call.args.dup,
      )
      replaced = false
      wrapper.blocks.each do |block|
        block.instructions.each_with_index do |instruction, index|
          next unless instruction.same?(call)
          block.replace(index.to_i32, replacement_call)
          replaced = true
          break
        end
      end
      raise "initializer call was not found while preparing NoReturn wrapper" unless replaced

      wrapper.return_type = no_return
      wrapper.get_block(wrapper.entry_block).terminator = Adamas::HIR::Unreachable.new
      @function_types[wrapper.name] = no_return
      set_function_state(wrapper.name, FunctionLoweringState::Completed)
      recipe = @generated_allocator_layout_recipes[wrapper.name]
      @generated_allocator_layout_bodies[wrapper.name] = {wrapper, wrapper.body_revision, recipe.class_name}
    end

    # The source fixture has already retired its original initializer. Install
    # a fresh body with the same exact source recipe and parameter ABI, varying
    # only the result's NoReturn category. The placeholder normal body is a
    # test-only HIR witness; these cases exercise receipt renewal, not source
    # reachability or code generation.
    @module.remove_function(name) if @module.function_by_name(name)
    clear_function_state(name)
    result_type = prior_is_noreturn ? original.return_type : no_return
    replacement = @module.create_function(name, result_type)
    old_function.params.each do |param|
      replacement.add_param(param.name, param.type, param.is_block)
    end
    replacement.heap_block_param = old_function.heap_block_param
    entry = replacement.get_block(replacement.entry_block)
    if noreturn_type?(result_type)
      entry.terminator = Adamas::HIR::Unreachable.new
    else
      literal = Adamas::HIR::Literal.new(replacement.next_value_id, result_type, 0_i64)
      entry.add(literal)
      entry.terminator = Adamas::HIR::Return.new(literal.id)
    end
    set_function_state(name, FunctionLoweringState::Completed)
    @function_types[name] = result_type

    current = __test_copy_initializer_source(prior, replacement, result_type, false)
    @materialized_initializer_sources[name] = current
    after = __test_generated_initializer_receipt(name)
    {
      prior: prior,
      current: current,
      wrapper: after[:wrapper],
      call: after[:call],
      old_target: old_function,
    }
  end

  private def __test_copy_initializer_source(
    source : MaterializedInitializerSource,
    function : Adamas::HIR::Function,
    return_type : Adamas::HIR::TypeRef,
    invalidated : Bool,
  ) : MaterializedInitializerSource
    MaterializedInitializerSource.new(
      function, source.source_name, source.source_def, source.source_arena,
      source.namespace, source.bindings.dup, source.registered_base_name,
      source.registered_target_bindings.try(&.dup), source.registered_base_bindings.try(&.dup),
      source.parameter_types.dup, source.block_parameters.dup, source.heap_block_param,
      source.callback_abi, source.callback_source, return_type, source.owner, source.owner_type,
      source.lowering_namespace, source.lowering_bindings.dup, source.call_types.try(&.dup),
      source.call_literals.try(&.dup), source.call_enum_names.try(&.dup), invalidated,
    )
  end

  def __test_no_return_transition_preconditions(state) : Array(Bool)
    prior = state[:prior]
    current = state[:current]
    wrapper = state[:wrapper]
    call = state[:call]
    contract = @generated_allocator_layout_recipes[wrapper.name].initializer_call.not_nil!
    [
      prior.return_result_invalidated,
      !current.return_result_invalidated,
      prior.function.return_type == prior.return_type,
      initializer_source_recipe_matches?(prior, current),
      initializer_source_definition_current?(prior),
      materialized_initializer_source_current?(current),
      initializer_source_return_update_admitted?(prior, current, prior),
      !prior.function.same?(current.function),
      contract.source.def_node.same?(prior.source_def),
      contract.source.source_arena.try { |arena| arena_map_key(arena) == arena_map_key(prior.source_arena) } || false,
      contract.param_types == prior.parameter_types,
      prior.function.params.map(&.type) == prior.parameter_types,
      prior.function.params.map(&.is_block) == prior.block_parameters,
      prior.function.heap_block_param == prior.heap_block_param,
      current.function.params.map(&.type) == current.parameter_types,
      current.function.params.map(&.is_block) == current.block_parameters,
      current.function.heap_block_param == current.heap_block_param,
      @module.function_by_name(current.function.name).try(&.same?(current.function)) || false,
      materialized_generated_allocator(wrapper.name).try(&.same?(wrapper)) || false,
      generated_allocator_initializer_call_shape_matches?(call, contract),
      call.type == prior.return_type,
      noreturn_type?(prior.return_type) != noreturn_type?(current.return_type),
      contract.target.same?(state[:old_target]),
    ]
  end

  def __test_refresh_initializer_receipt(prior, current) : Symbol
    refresh_generated_initializer_call_receipts(prior, current)
    :completed
  rescue ex : Adamas::HIR::LoweringError
    unless ex.details.starts_with?("generated allocator initializer cannot renew its replay receipt:")
      raise ex
    end
    :renewal_refused
  end

  def __test_replay_initializer(name : String) : Symbol
    replay_materialized_initializer(name)
    :completed
  rescue ex : Adamas::HIR::LoweringError
    unless ex.details.starts_with?("generated allocator initializer cannot renew its replay receipt:") ||
           ex.details.starts_with?("generated allocator initializer replay changed its source or ABI:")
      raise ex
    end
    :renewal_refused
  end

  def __test_flush_pending_functions : Symbol
    flush_pending_functions
    :completed
  rescue ex : Adamas::HIR::LoweringError
    unless ex.details.starts_with?("generated allocator initializer lost its selected source or ABI:")
      raise ex
    end
    :stale_initializer_receipt
  end

  def __test_generated_allocator_is_materialized?(name : String) : Bool
    !materialized_generated_allocator(name).nil?
  end

  def __test_strict_initializer_receipt_valid?(wrapper : Adamas::HIR::Function, call : Adamas::HIR::Call) : Bool
    generated_allocator_initializer_call?(wrapper, call, require_settled_result: true)
  rescue ex : Adamas::HIR::LoweringError
    false
  end

  def __test_install_untracked_same_name_function(name : String, old_function : Adamas::HIR::Function) : Adamas::HIR::Function
    @module.remove_function(name) if @module.function_by_name(name)
    replacement = @module.create_function(name, old_function.return_type)
    old_function.params.each do |param|
      replacement.add_param(param.name, param.type, param.is_block)
    end
    replacement.heap_block_param = old_function.heap_block_param

    entry = replacement.get_block(replacement.entry_block)
    if replacement.return_type == Adamas::HIR::TypeRef::VOID
      entry.terminator = Adamas::HIR::Return.new(nil)
    else
      value = Adamas::HIR::Literal.new(replacement.next_value_id, replacement.return_type, 1_i64)
      entry.add(value)
      entry.terminator = Adamas::HIR::Return.new(value.id)
    end
    replacement
  end
end

private def lower_natural_initializer_replay_receipt_fixture : Adamas::HIR::AstToHir
  code = <<-CRYSTAL
    class NaturalInitializerReplayOwner
      def initialize(&@callback)
        @callback
      end
    end
    NaturalInitializerReplayOwner.new { 65 }
  CRYSTAL
  parsed = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(code)
  ).parse_program
  converter = Adamas::HIR::AstToHir.new(parsed.arena)
  converter.arena = parsed.arena
  main = [] of UInt64
  parsed.roots.each do |id|
    case node = parsed.arena[id]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
      converter.lower_class(node)
    else
      main << id.index.to_u64
    end
  end
  # Keep the source-owned initializer retired until the real pending flush.
  converter.lower_main(main)
  converter
end

describe "generated allocator initializer replay receipts" do
  it "refreshes the exact receipt after the natural captured-block replay" do
    converter = lower_natural_initializer_replay_receipt_fixture
    name = converter.__test_natural_initializer_receipt_name
    before_source = converter.__test_initializer_source(name)
    before = converter.__test_generated_initializer_receipt(name)

    before[:contract].target.same?(before_source.function).should be_true
    converter.module.function_by_name(name).try(&.same?(before_source.function)).should_not be_true
    before_source.return_result_invalidated.should be_true

    # The baseline can stop inside stale-call repair on this exact receipt
    # mismatch. Catch only that known failure so the test can assert the stale
    # target identity directly; unrelated lowering errors still fail the spec.
    converter.__test_flush_pending_functions

    after_source = converter.__test_initializer_source(name)
    after = converter.__test_generated_initializer_receipt(name)
    current_function = converter.module.function_by_name(name).not_nil!
    after_source.return_result_invalidated.should be_false
    after_source.function.same?(current_function).should be_true
    after[:contract].target.same?(current_function).should be_true
    after[:contract].source.def_node.same?(before[:contract].source.def_node).should be_true
    after[:contract].source.source_arena.not_nil!.same?(before[:contract].source.source_arena.not_nil!).should be_true
    after[:contract].param_types.should eq(current_function.params.map(&.type))
    after[:call].type.should eq(current_function.return_type)
    converter.__test_strict_initializer_receipt_valid?(after[:wrapper], after[:call]).should be_true
  end

  it "does not renew a normal wrapper receipt across a normal-to-NoReturn result change" do
    converter = lower_natural_initializer_replay_receipt_fixture
    name = converter.__test_natural_initializer_receipt_name
    state = converter.__test_prepare_no_return_transition(name, prior_is_noreturn: false)
    before_call_type = state[:call].type
    before_wrapper_type = state[:wrapper].return_type
    before_terminator = state[:wrapper].get_block(state[:wrapper].entry_block).terminator

    converter.__test_no_return_transition_preconditions(state).all? { |valid| valid }.should be_true
    converter.__test_refresh_initializer_receipt(state[:prior], state[:current]).should eq(:renewal_refused)

    state[:prior].return_type.should_not eq(state[:current].return_type)
    state[:call].type.should eq(before_call_type)
    state[:wrapper].return_type.should eq(before_wrapper_type)
    state[:wrapper].get_block(state[:wrapper].entry_block).terminator.same?(before_terminator).should be_true
    state[:wrapper].get_block(state[:wrapper].entry_block).terminator.is_a?(Adamas::HIR::Unreachable).should be_false
    converter.__test_generated_initializer_receipt(name)[:contract].target.same?(state[:old_target]).should be_true
    converter.__test_strict_initializer_receipt_valid?(state[:wrapper], state[:call]).should be_false
  end

  it "does not renew a NoReturn wrapper receipt across a NoReturn-to-normal result change" do
    converter = lower_natural_initializer_replay_receipt_fixture
    name = converter.__test_natural_initializer_receipt_name
    state = converter.__test_prepare_no_return_transition(name, prior_is_noreturn: true)

    converter.__test_no_return_transition_preconditions(state).all? { |valid| valid }.should be_true
    state[:wrapper].return_type.should eq(state[:prior].return_type)
    state[:call].type.should eq(state[:prior].return_type)
    state[:wrapper].get_block(state[:wrapper].entry_block).terminator.is_a?(Adamas::HIR::Unreachable).should be_true
    converter.__test_refresh_initializer_receipt(state[:prior], state[:current]).should eq(:renewal_refused)

    state[:prior].return_type.should_not eq(state[:current].return_type)
    state[:wrapper].return_type.should eq(state[:prior].return_type)
    state[:call].type.should eq(state[:prior].return_type)
    state[:wrapper].get_block(state[:wrapper].entry_block).terminator.is_a?(Adamas::HIR::Unreachable).should be_true
    converter.__test_generated_initializer_receipt(name)[:contract].target.same?(state[:old_target]).should be_true
    converter.__test_strict_initializer_receipt_valid?(state[:wrapper], state[:call]).should be_false
  end

  {% for mutation in [:args, :receiver, :target] %}
    it "does not refresh a receipt when the live call {{ mutation.id }} changes" do
      converter = lower_natural_initializer_replay_receipt_fixture
      name = converter.__test_natural_initializer_receipt_name
      before = converter.__test_generated_initializer_receipt(name)
      old_target = before[:contract].target
      revision = before[:wrapper].body_revision

      {% if mutation.id == :args %}
        before[:call].args.should_not be_empty
        before[:call].args[0] = before[:call].receiver_value
      {% elsif mutation.id == :receiver %}
        before[:call].args.should_not be_empty
        before[:call].args.first.should_not eq(before[:call].receiver_value)
        before[:call].configure_with_receiver(
          before[:call].args.first,
          before[:call].method_name,
          before[:call].args.dup,
          false,
        )
      {% else %}
        before[:call].method_name = "#{name}$untracked"
      {% end %}

      # These in-place Call mutations leave the wrapper revision witness intact;
      # receipt refresh must still compare the live instruction to its capture.
      before[:wrapper].body_revision.should eq(revision)
      converter.__test_generated_allocator_is_materialized?(before[:wrapper].name).should be_true
      converter.__test_replay_initializer(name)

      after = converter.__test_generated_initializer_receipt(name)
      after[:contract].target.same?(old_target).should be_true
      converter.module.function_by_name(name).not_nil!.same?(old_target).should be_false
      converter.__test_strict_initializer_receipt_valid?(after[:wrapper], after[:call]).should be_false
    end
  {% end %}

  it "does not refresh a receipt after its generated wrapper witness becomes stale" do
    converter = lower_natural_initializer_replay_receipt_fixture
    name = converter.__test_natural_initializer_receipt_name
    before = converter.__test_generated_initializer_receipt(name)
    old_target = before[:contract].target

    block = before[:wrapper].get_block(before[:wrapper].entry_block)
    block.add(Adamas::HIR::Literal.new(before[:wrapper].next_value_id, Adamas::HIR::TypeRef::INT32, 0_i64))
    converter.__test_generated_allocator_is_materialized?(before[:wrapper].name).should be_false
    converter.__test_replay_initializer(name)

    after = converter.__test_generated_initializer_receipt(name)
    after[:contract].target.same?(old_target).should be_true
    converter.module.function_by_name(name).not_nil!.same?(old_target).should be_false
    converter.__test_strict_initializer_receipt_valid?(after[:wrapper], after[:call]).should be_false
  end

  it "rejects an untracked same-name Function replacement with the same ABI" do
    converter = lower_natural_initializer_replay_receipt_fixture
    name = converter.__test_natural_initializer_receipt_name
    receipt = converter.__test_generated_initializer_receipt(name)
    old_target = receipt[:contract].target

    replacement = converter.__test_install_untracked_same_name_function(name, old_target)
    replacement.same?(old_target).should be_false
    replacement.params.map(&.type).should eq(receipt[:contract].param_types)
    converter.module.has_function_with_body?(name).should be_true
    converter.__test_strict_initializer_receipt_valid?(receipt[:wrapper], receipt[:call]).should be_false
    receipt[:contract].target.same?(old_target).should be_true
  end
end
