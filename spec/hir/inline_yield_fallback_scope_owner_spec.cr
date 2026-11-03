require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

alias FallbackContextState = Tuple(Int32, Int32, Int32, Int32, Int32, String)
alias FallbackCacheState = Tuple(Int32, Int32, Int32, String)

class Adamas::HIR::LoweringContext
  def __test_fallback_scope_state : FallbackContextState
    structural_state = {
      @scope_stack.dup,
      @locals_snapshots.map(&.dup),
      @debug_local_snapshots.map(&.dup),
      @boxed_locals_snapshots.map(&.dup),
      @block_parameter_binding_snapshots.map(&.dup),
      @current_block,
      @locals.dup,
      @debug_local_ids.dup,
      @boxed_locals.dup,
      @block_parameter_bindings.dup,
      @local_declaration_scopes.map(&.dup),
      @self_id,
    }
    {@scope_stack.size, @locals_snapshots.size, @debug_local_snapshots.size,
     @boxed_locals_snapshots.size, @block_parameter_binding_snapshots.size,
     structural_state.inspect}
  end
end

class Adamas::HIR::AstToHir
  def __test_fallback_cache_state : FallbackCacheState
    exact_cache_state = {
      @block_lowering_cache,
      @block_lowering_in_progress,
      @block_captures,
      @block_node_arenas,
      @block_owner,
      @block_owner_function_ids,
      @block_owner_self_ids,
      @last_block_arena_id,
      @last_block_arena.try(&.object_id),
    }.inspect
    {@block_lowering_cache.size, @block_lowering_in_progress.size,
     @block_captures.size, exact_cache_state}
  end

  def __test_fallback_ambient_state : String
    stack_state = {
      __test_stack_identity(@loop_exit_stack),
      __test_stack_identity(@loop_cond_stack),
      __test_stack_identity(@loop_inline_next_depth_stack),
      __test_stack_identity(@loop_phi_stack),
      __test_stack_identity(@loop_break_info_stack),
      __test_stack_identity(@loop_break_value_stack),
      __test_stack_identity(@loop_break_inline_locals_stack),
      __test_stack_identity(@inline_next_stack),
      __test_stack_identity(@inline_tuple_each_next_stack),
      __test_stack_identity(@inline_tuple_each_loop_exit_depth_stack),
      __test_stack_identity(@inline_yield_return_stack),
      __test_stack_identity(@inline_yield_return_override_stack),
      __test_stack_identity(@inline_caller_locals_stack),
      __test_stack_identity(@inline_caller_local_declaration_scopes_stack),
      __test_stack_identity(@inline_caller_function_id_stack),
      __test_stack_identity(@inline_yield_block_stack),
      __test_stack_identity(@inline_yield_block_arena_stack),
      __test_stack_identity(@inline_yield_block_param_types_stack),
      __test_stack_identity(@inline_yield_block_return_stack),
      __test_stack_identity(@inline_yield_name_stack),
      __test_stack_identity(@inline_yield_return_caller_locals_stack),
    }
    typeof_locals_id = @current_typeof_locals.try(&.object_id)
    typeof_names_id = @current_typeof_local_names.try(&.object_id)
    {
      @arena.object_id,
      @current_class,
      @current_method,
      @current_method_is_class,
      @current_namespace_override,
      stack_state,
      typeof_locals_id,
      @current_typeof_locals.try(&.inspect),
      typeof_names_id,
      @current_typeof_local_names.try(&.inspect),
      @current_typeof_local_names_hash,
      @current_typeof_local_names_hash_owner,
      @inline_yield_function_depth,
      @inline_yield_block_body_depth,
      @inline_yield_proc_depth,
      @suppress_force_lower_return_type_depth,
    }.inspect
  end

  private def __test_stack_identity(stack : Array(T)) : Tuple(UInt64, Int32, String) forall T
    {stack.object_id.to_u64, stack.size, stack.inspect}
  end

  # This is a test entry only: exercise the real private fallback boundary with
  # a selected source definition and its actual BlockNode.
  def __test_call_inline_yield_fallback(
    ctx : LoweringContext,
    inline_key : String,
    block : Adamas::Compiler::Frontend::BlockNode,
    selected_def : Adamas::Compiler::Frontend::DefNode,
    selected_arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : ValueId
    inline_yield_fallback_call(
      ctx,
      inline_key,
      nil,
      [] of ValueId,
      block,
      selected_def,
      selected_arena,
    )
  end
end

private def fallback_scope_owner_probe(
  body : String,
  nested : Bool = false,
  disabled_inline_yield : Bool = false,
)
  source = <<-CRYSTAL
    def fallback_scope_value(&) : Int32
      yield
    end
    def fallback_scope_outer(&) : Int32
      fallback_scope_value { yield }
    end
    #{body}
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
  converter.no_prelude = true
  main = [] of UInt64
  program.roots.each do |id|
    if node = arena[id].as?(Adamas::Compiler::Frontend::DefNode)
      converter.register_function(node)
    else
      main << id.index.to_u64
    end
  end
  old_disable = ENV["ADAMAS_DISABLE_INLINE_YIELD"]?
  old_depth = ENV["INLINE_YIELD_MAX_DEPTH"]?
  lowering_error = nil.as(Exception?)
  function = nil.as(Adamas::HIR::Function?)
  begin
    if disabled_inline_yield
      ENV["ADAMAS_DISABLE_INLINE_YIELD"] = "1"
    else
      ENV.delete("ADAMAS_DISABLE_INLINE_YIELD")
    end
    ENV["INLINE_YIELD_MAX_DEPTH"] = nested ? "1" : "0"
    function = converter.lower_main(main)
    converter.flush_pending_functions
  rescue error : Exception
    lowering_error = error
  ensure
    if old_disable
      ENV["ADAMAS_DISABLE_INLINE_YIELD"] = old_disable
    else
      ENV.delete("ADAMAS_DISABLE_INLINE_YIELD")
    end
    if old_depth
      ENV["INLINE_YIELD_MAX_DEPTH"] = old_depth
    else
      ENV.delete("INLINE_YIELD_MAX_DEPTH")
    end
  end
  {converter, lowering_error, function}
end

private def direct_fallback_failure_probe
  source = <<-CRYSTAL
    def fallback_scope_value(&) : Int32
      yield
    end
    fallback_scope_value { MissingFallbackScopeOwner }
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  selected_def = nil.as(Adamas::Compiler::Frontend::DefNode?)
  call = nil.as(Adamas::Compiler::Frontend::CallNode?)
  program.roots.each do |id|
    node = arena[id]
    if definition = node.as?(Adamas::Compiler::Frontend::DefNode)
      selected_def = definition
    elsif source_call = node.as?(Adamas::Compiler::Frontend::CallNode)
      call = source_call
    end
  end
  definition = selected_def.not_nil!
  source_call = call.not_nil!
  block_id = source_call.block.not_nil!
  block = arena[block_id].as(Adamas::Compiler::Frontend::BlockNode)

  converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
  converter.no_prelude = true
  converter.register_function(definition)
  function = converter.module.create_function("__fallback_scope_direct_probe", Adamas::HIR::TypeRef::INT32)
  ctx = Adamas::HIR::LoweringContext.new(function, converter.module, arena)

  context_before = ctx.__test_fallback_scope_state
  ambient_before = converter.__test_fallback_ambient_state
  cache_before = converter.__test_fallback_cache_state
  error = nil.as(Adamas::HIR::LoweringError?)
  begin
    converter.__test_call_inline_yield_fallback(
      ctx,
      "fallback_scope_value$block",
      block,
      definition,
      arena,
    )
  rescue caught : Adamas::HIR::LoweringError
    error = caught
  end
  {
    error,
    context_before,
    ctx.__test_fallback_scope_state,
    ambient_before,
    converter.__test_fallback_ambient_state,
    cache_before,
    converter.__test_fallback_cache_state,
  }
end

private def assert_assignment_uses_function_scope(function : Adamas::HIR::Function, name : String)
  function_scope = function.scopes.first
  function_scope.kind.should eq(Adamas::HIR::ScopeKind::Function)
  locals = function.blocks.flat_map(&.instructions).compact_map do |instruction|
    instruction.as?(Adamas::HIR::Local)
  end.select { |local| local.name == name && local.scope == function_scope.id }
    locals.should_not be_empty, "#{name} was not assigned in the caller function scope"
  locals.each do |local|
    function_scope.locals.should contain(local.id)
  end
end

describe "inline yield fallback scope ownership" do
  it "preserves the root scope for the next assignment" do
    _, error, function = fallback_scope_owner_probe("fallback_scope_value { 1 }; after = 65; after")
    error.should be_nil
    assert_assignment_uses_function_scope(function.not_nil!, "after")
  end

  it "preserves a surrounding inline scope when a nested call falls back" do
    _, error, function = fallback_scope_owner_probe("fallback_scope_outer { 1 }; after = 65; after", nested: true)
    error.should be_nil
    assert_assignment_uses_function_scope(function.not_nil!, "after")
  end

  it "preserves the caller scope after writing a mutable capture" do
    _, error, function = fallback_scope_owner_probe("letter = 66; fallback_scope_value { letter = 65 }; after = letter; after")
    error.should be_nil
    main = function.not_nil!
    assert_assignment_uses_function_scope(main, "letter")
    assert_assignment_uses_function_scope(main, "after")
  end

  it "preserves the root scope when inline yield is disabled" do
    _, error, function = fallback_scope_owner_probe(
      "fallback_scope_value { 1 }; after = 65; after",
      disabled_inline_yield: true,
    )
    error.should be_nil
    assert_assignment_uses_function_scope(function.not_nil!, "after")
  end

  it "propagates the original block error after the depth guard falls back" do
    _, error, _ = fallback_scope_owner_probe(
      "fallback_scope_value { MissingFallbackScopeOwner }",
    )
    error.should_not be_nil
    error.not_nil!.message.not_nil!.should eq("undefined constant MissingFallbackScopeOwner")
  end

  it "propagates the original block error when inline yield is disabled" do
    _, error, _ = fallback_scope_owner_probe(
      "fallback_scope_value { MissingFallbackScopeOwner }",
      disabled_inline_yield: true,
    )
    error.should_not be_nil
    error.not_nil!.message.not_nil!.should eq("undefined constant MissingFallbackScopeOwner")
  end

  it "restores caller, ambient, and cache state while propagating a block body error" do
    error, context_before, context_after, ambient_before, ambient_after, cache_before, cache_after =
      direct_fallback_failure_probe

    error.should_not be_nil
    error.not_nil!.message.not_nil!.should eq("undefined constant MissingFallbackScopeOwner")
    context_after.should eq(context_before)
    ambient_after.should eq(ambient_before)
    cache_after.should eq(cache_before)
    cache_after[0].should eq(0)
    cache_after[1].should eq(0)
    cache_after[2].should eq(0)
  end
end
