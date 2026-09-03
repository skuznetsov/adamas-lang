require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/semantic/analyzer"

# Layout-compatible proxy for the self-host failure mode where an arena node
# keeps its InstanceVarDecl payload and tag but loses concrete subclass RTTI.
class ErasedInstanceVarDeclNode < Adamas::Compiler::Frontend::Node
  getter span : Adamas::Compiler::Frontend::Span
  getter name : Slice(UInt8)
  getter type : Slice(UInt8)
  getter value : Adamas::Compiler::Frontend::ExprId?

  def initialize(
    @span : Adamas::Compiler::Frontend::Span,
    @name : Slice(UInt8),
    @type : Slice(UInt8),
    @value : Adamas::Compiler::Frontend::ExprId? = nil,
  )
  end

  def node_kind : Adamas::Compiler::Frontend::NodeKind
    Adamas::Compiler::Frontend::NodeKind::InstanceVarDecl
  end
end

private CORRUPTED_PARAMETER_TYPE_SOURCE = "Nil"

private def unreadable_parameter_type_annotation : Slice(UInt8)
  Slice(UInt8).new(Pointer(UInt8).new(1_u64), 1)
end

private def lose_nonempty_typed_parameter_metadata(
  arena : Adamas::Compiler::Frontend::ArenaLike,
  exprs : Array(Adamas::Compiler::Frontend::ExprId),
) : Nil
  exprs.each do |expr_id|
    node = arena[expr_id]
    case node
    when Adamas::Compiler::Frontend::ModuleNode
      lose_nonempty_typed_parameter_metadata(arena, node.body.not_nil!) if node.body
    when Adamas::Compiler::Frontend::ClassNode
      lose_nonempty_typed_parameter_metadata(arena, node.body.not_nil!) if node.body
    when Adamas::Compiler::Frontend::BlockNode
      lose_nonempty_typed_parameter_metadata(arena, node.body)
    when Adamas::Compiler::Frontend::DefNode
      if (safe_name = node.name) && String.new(safe_name) == "initialize"
        params = node.params
        if params
          replacement = [] of Adamas::Compiler::Frontend::Parameter
          params.each do |param|
            type_annotation = param.type_annotation
            type_text = type_annotation ? String.new(type_annotation) : ""
            if type_annotation &&
               (type_text.includes?("Slice(") || type_text.includes?("Array(") || type_text.ends_with?("?"))
              replacement << Adamas::Compiler::Frontend::Parameter.new(
                param.name,
                param.external_name,
                CORRUPTED_PARAMETER_TYPE_SOURCE.to_slice,
                param.default_value,
                param.span,
                param.name_span,
                param.external_name_span,
                nil,
                param.default_span,
                param.is_splat,
                param.is_double_splat,
                param.is_block,
                param.is_instance_var,
              )
            else
              replacement << param
            end
          end
          params.clear
          params.concat(replacement)
        end
      end
      lose_nonempty_typed_parameter_metadata(arena, node.body.not_nil!) if node.body
    end
  end
end

private def replace_nonempty_typed_parameter_annotation_payload(
  arena : Adamas::Compiler::Frontend::ArenaLike,
  exprs : Array(Adamas::Compiler::Frontend::ExprId),
) : Nil
  exprs.each do |expr_id|
    node = arena[expr_id]
    case node
    when Adamas::Compiler::Frontend::ModuleNode
      replace_nonempty_typed_parameter_annotation_payload(arena, node.body.not_nil!) if node.body
    when Adamas::Compiler::Frontend::ClassNode
      replace_nonempty_typed_parameter_annotation_payload(arena, node.body.not_nil!) if node.body
    when Adamas::Compiler::Frontend::BlockNode
      replace_nonempty_typed_parameter_annotation_payload(arena, node.body)
    when Adamas::Compiler::Frontend::DefNode
      if (safe_name = node.name) && String.new(safe_name) == "initialize"
        if params = node.params
          replacement = [] of Adamas::Compiler::Frontend::Parameter
          params.each do |param|
            if param.type_annotation
              replacement << Adamas::Compiler::Frontend::Parameter.new(
                param.name,
                param.external_name,
                unreadable_parameter_type_annotation,
                param.default_value,
                param.span,
                param.name_span,
                param.external_name_span,
                param.type_span,
                param.default_span,
                param.is_splat,
                param.is_double_splat,
                param.is_block,
                param.is_instance_var,
              )
            else
              replacement << param
            end
          end
          params.clear
          params.concat(replacement)
        end
      end
      replace_nonempty_typed_parameter_annotation_payload(arena, node.body.not_nil!) if node.body
    end
  end
end

# Reproduce the self-host loss mode for an anonymous typed block parameter:
# retain the block/name shape but replace its readable proc annotation with a
# stale ordinary token and drop the dedicated type span. Source recovery must
# use `& : String ->` as the authoritative witness and restore the proc type.
private def corrupt_anonymous_typed_block_parameter(
  arena : Adamas::Compiler::Frontend::ArenaLike,
  exprs : Array(Adamas::Compiler::Frontend::ExprId),
) : Nil
  exprs.each do |expr_id|
    node = arena[expr_id]
    case node
    when Adamas::Compiler::Frontend::ModuleNode
      corrupt_anonymous_typed_block_parameter(arena, node.body.not_nil!) if node.body
    when Adamas::Compiler::Frontend::ClassNode
      corrupt_anonymous_typed_block_parameter(arena, node.body.not_nil!) if node.body
    when Adamas::Compiler::Frontend::BlockNode
      corrupt_anonymous_typed_block_parameter(arena, node.body)
    when Adamas::Compiler::Frontend::DefNode
      if params = node.params
        replacement = [] of Adamas::Compiler::Frontend::Parameter
        params.each do |param|
          type_text = param.type_annotation.try { |slice| String.new(slice) }
          if param.is_block && param.name.nil? && type_text == "String ->"
            replacement << Adamas::Compiler::Frontend::Parameter.new(
              param.name,
              param.external_name,
              CORRUPTED_PARAMETER_TYPE_SOURCE.to_slice,
              param.default_value,
              param.span,
              param.name_span,
              param.external_name_span,
              nil,
              param.default_span,
              param.is_splat,
              param.is_double_splat,
              param.is_block,
              param.is_instance_var,
            )
          else
            replacement << param
          end
        end
        params.clear
        params.concat(replacement)
      end
      corrupt_anonymous_typed_block_parameter(arena, node.body.not_nil!) if node.body
    end
  end
end

# Test-only access to private parsing helpers (keeps production API small).
class Adamas::HIR::AstToHir
  def __test_begin_call_resolution_profile : Nil
    @call_resolution_profile_count = 0_i64
    @call_resolution_profile_active = true
  end

  def __test_call_resolution_profile_count : Int64
    @call_resolution_profile_count
  end

  def __test_reset_call_resolution_memo : Nil
    @call_resolution_memo.clear
    @call_resolution_memo_enabled = true
    @call_resolution_memo_hits = 0_i64
    @call_resolution_memo_misses = 0_i64
    @call_resolution_memo_store_skips = 0_i64
  end

  def __test_call_resolution_memo_stats
    {
      entries:     @call_resolution_memo.size,
      hits:        @call_resolution_memo_hits,
      misses:      @call_resolution_memo_misses,
      store_skips: @call_resolution_memo_store_skips,
    }
  end

  def __test_resolve_call_memo(
    name : String,
    arg_types : Array(Adamas::HIR::TypeRef),
    type_params : Hash(String, String)? = nil,
  ) : {String?, UInt64?}
    old_type_params = @type_param_map
    @type_param_map = type_params if type_params
    begin
      target = resolve_call_target(CallResolutionInput.new(
        func_name: name,
        arg_count: arg_types.size,
        arg_types: arg_types,
        has_block: false,
        has_splat: false,
        has_named: false,
        named_names: nil,
      ))
      {target.try(&.symbol_name), target.try { |selected| selected.def_node.object_id.to_u64 }}
    ensure
      @type_param_map = old_type_params
    end
  end

  def __test_reregister_function_def(name : String) : Nil
    def_node = @function_defs[name]? || raise "missing function def fixture: #{name}"
    set_function_def_entry(name, def_node, record_current_arena: false)
  end

  def __test_add_function_def_alias(source_name : String, alias_name : String) : Nil
    def_node = @function_defs[source_name]? || raise "missing function def fixture: #{source_name}"
    set_function_def_entry(alias_name, def_node, record_current_arena: false)
  end

  def __test_method_index_state
    {
      built:         @method_index_built,
      size_at_build: @method_index_size_at_build,
      processed:     @method_index_processed_count,
      defs_size:     @function_defs.size,
    }
  end

  def __test_method_index_candidates(
    owner : String,
    method_name : String,
    separator : Char = '#',
  ) : Array(String)
    ensure_method_index_built
    owner_methods = @method_index[method_index_owner_key(owner)]? || return [] of String
    bucket = owner_methods[method_name]? || return [] of String
    method_index_candidates_for_separator(bucket, separator).dup
  end

  def __test_method_index_all_candidates(owner : String, method_name : String) : Array(String)
    ensure_method_index_built
    owner_methods = @method_index[method_index_owner_key(owner)]? || return [] of String
    owner_methods[method_name]?.try(&.all_candidates.dup) || [] of String
  end

  def __test_perturb_unrelated_lowering_work(name : String) : Nil
    set_function_state(name, FunctionLoweringState::Pending)
    enqueue_pending_function(name, "call_resolution_memo_spec")
  end

  def __test_perturb_unrelated_hir_work(name : String) : Nil
    function = @module.create_function(name, Adamas::HIR::TypeRef::NIL)
    function.create_block(function.get_block(function.entry_block).scope)
  end

  def __test_record_module_inclusion(module_name : String, class_name : String) : Nil
    record_module_inclusion(module_name, class_name)
  end

  def __test_resolve_signature_short_name(name : String, candidates : Set(String)) : String?
    @short_type_index[name] = candidates
    resolve_class_name_in_signature_context(name)
  end

  def __test_resolve_signature_short_name_without_entry(name : String) : String?
    resolve_class_name_in_signature_context(name)
  end

  def __test_short_type_index_has_key(name : String) : Bool
    @short_type_index.has_key?(name)
  end

  def __test_strip_callsite_splat_suffix(name : String) : String
    strip_callsite_splat_suffix(name)
  end

  def __test_strip_type_suffix(name : String) : String
    strip_type_suffix(name)
  end

  def __test_parse_method_name_compact(name : String) : {String, String?, Char?, String}
    parts = parse_method_name_compact(name)
    {parts.owner, parts.method, parts.separator, parts.base}
  end

  def __test_method_index_call_candidates_for_separator(
    candidates : Array(String),
    separator : Char,
  ) : Array(String)
    bucket = MethodIndexBucket.new
    candidates.each do |candidate|
      parts = parse_method_name_compact(candidate)
      next unless parts.separator && parts.method
      bucket.append(candidate, parts.separator.not_nil!)
    end
    method_index_call_candidates_for_separator(bucket, separator)
  end

  def __test_collect_assigned_vars(body : Array(Adamas::Compiler::Frontend::ExprId)) : Array(String)
    collect_assigned_vars(body)
  end

  def __test_lower_times_with_foreign_current_arena(
    block : Adamas::Compiler::Frontend::BlockNode,
    block_arena : Adamas::Compiler::Frontend::ArenaLike,
    foreign_arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Adamas::HIR::Function
    self.arena = foreign_arena
    function = @module.create_function("__test_times_foreign_arena", Adamas::HIR::TypeRef::NIL)
    ctx = Adamas::HIR::LoweringContext.new(function, @module, foreign_arena)
    count = Adamas::HIR::Literal.new(ctx.next_id, Adamas::HIR::TypeRef::INT32, 16_i64)
    ctx.emit(count)
    ctx.register_type(count.id, Adamas::HIR::TypeRef::INT32)
    lower_times_intrinsic(ctx, count.id, block, block_arena)
    function
  end

  def __test_lower_array_each_with_stale_param(
    block : Adamas::Compiler::Frontend::BlockNode,
    block_arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Adamas::HIR::Function
    self.arena = block_arena
    function = @module.create_function("__test_array_each_stale_param", Adamas::HIR::TypeRef::NIL)
    ctx = Adamas::HIR::LoweringContext.new(function, @module, block_arena)
    element = Adamas::HIR::Literal.new(ctx.next_id, Adamas::HIR::TypeRef::UINT32, 7_i64)
    ctx.emit(element)
    ctx.register_type(element.id, Adamas::HIR::TypeRef::UINT32)
    array = Adamas::HIR::ArrayLiteral.new(ctx.next_id, Adamas::HIR::TypeRef::UINT32, [element.id])
    ctx.emit(array)
    ctx.register_type(array.id, type_ref_for_name("Array(UInt32)"))
    lower_array_each_dynamic(ctx, array.id, block)
    function
  end

  def __test_lower_array_find_dynamic_with_stale_param(
    block : Adamas::Compiler::Frontend::BlockNode,
    block_arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Adamas::HIR::Function
    self.arena = block_arena
    function = @module.create_function("__test_array_find_stale_param", Adamas::HIR::TypeRef::NIL)
    ctx = Adamas::HIR::LoweringContext.new(function, @module, block_arena)
    element = Adamas::HIR::Literal.new(ctx.next_id, Adamas::HIR::TypeRef::INT32, 0_i64)
    ctx.emit(element)
    ctx.register_type(element.id, Adamas::HIR::TypeRef::INT32)
    array = Adamas::HIR::ArrayLiteral.new(ctx.next_id, Adamas::HIR::TypeRef::INT32, [element.id])
    ctx.emit(array)
    ctx.register_type(array.id, type_ref_for_name("Array(Int32)"))
    lower_array_find_dynamic(ctx, array.id, block)
    function
  end

  def __test_lower_array_index_block_dynamic_with_stale_param(
    block : Adamas::Compiler::Frontend::BlockNode,
    block_arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Adamas::HIR::Function
    self.arena = block_arena
    function = @module.create_function("__test_array_index_block_stale_param", Adamas::HIR::TypeRef::NIL)
    ctx = Adamas::HIR::LoweringContext.new(function, @module, block_arena)
    element = Adamas::HIR::Literal.new(ctx.next_id, Adamas::HIR::TypeRef::INT32, 0_i64)
    ctx.emit(element)
    ctx.register_type(element.id, Adamas::HIR::TypeRef::INT32)
    array = Adamas::HIR::ArrayLiteral.new(ctx.next_id, Adamas::HIR::TypeRef::INT32, [element.id])
    ctx.emit(array)
    ctx.register_type(array.id, type_ref_for_name("Array(Int32)"))
    lower_array_index_block_dynamic(ctx, array.id, block)
    function
  end

  def __test_rebind_stale_box_same_type(
    arena : Adamas::Compiler::Frontend::ArenaLike,
    target_expr : Adamas::Compiler::Frontend::ExprId,
  ) : {Adamas::HIR::Function, Bool, Bool}
    self.arena = arena
    function = @module.create_function("__test_rebind_stale_box_same_type", Adamas::HIR::TypeRef::INT32)
    ctx = Adamas::HIR::LoweringContext.new(function, @module, arena)
    empty_locals = ctx.save_locals

    initial = Adamas::HIR::Literal.new(ctx.next_id, Adamas::HIR::TypeRef::INT32, 7_i64)
    ctx.emit(initial)
    ctx.register_type(initial.id, Adamas::HIR::TypeRef::INT32)
    local = Adamas::HIR::Local.new(ctx.next_id, Adamas::HIR::TypeRef::INT32, "first", ctx.current_scope)
    ctx.emit(local)
    ctx.register_local("first", local.id)
    ctx.require_entry_box_for_local("first")
    hoist_box_for_local(ctx, "first", Adamas::HIR::TypeRef::INT32, initial.id)
    ctx.restore_locals(empty_locals)
    missing_before_assignment = ctx.lookup_local("first").nil?

    replacement = Adamas::HIR::Literal.new(ctx.next_id, Adamas::HIR::TypeRef::INT32, 42_i64)
    ctx.emit(replacement)
    ctx.register_type(replacement.id, Adamas::HIR::TypeRef::INT32)
    assign_value_to_target(ctx, target_expr, replacement.id)
    visible_after_assignment = !ctx.lookup_local("first").nil?
    target_node = @arena[target_expr].unsafe_as(Adamas::Compiler::Frontend::IdentifierNode)
    read_id = lower_identifier(ctx, target_node)
    ctx.terminate(Adamas::HIR::Return.new(read_id))
    {function, missing_before_assignment, visible_after_assignment}
  end

  def __test_split_generic_type_args(params_str : String) : Array(String)
    split_generic_type_args(params_str)
  end

  def __test_safe_slice_to_string(slice : Slice(UInt8)) : String?
    safe_slice_to_string(slice)
  end

  def __test_has_protected_access_to(current_name : String, owner_name : String) : Bool
    has_protected_access_to?(current_name, owner_name)
  end

  def __test_safe_slice_guard?(slice : Slice(UInt8)) : Bool
    safe_slice_guard?(slice)
  end

  def __test_store_extra_source(
    arena : Adamas::Compiler::Frontend::ArenaLike,
    text : String,
  ) : Nil
    store_extra_source(arena, text)
  end

  def __test_parameter_slice_from_foreign_retained_source?(
    slice : Slice(UInt8),
    arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Bool
    parameter_slice_from_foreign_retained_source?(slice, arena)
  end

  def __test_set_source_for_arena(
    arena : Adamas::Compiler::Frontend::ArenaLike,
    source : String,
  ) : String
    set_source_for_arena(arena, source)
  end

  def __test_parameter_type_annotation_from_source(
    param : Adamas::Compiler::Frontend::Parameter,
    arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : String?
    parameter_type_annotation_string(param, arena, false)
  end

  def __test_source_recovered_def_for(
    node : Adamas::Compiler::Frontend::DefNode,
    arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Adamas::Compiler::Frontend::DefNode?
    source_recovered_def_for(node, arena)
  end

  def __test_source_recovered_def_for_with_owner(
    node : Adamas::Compiler::Frontend::DefNode,
    arena : Adamas::Compiler::Frontend::ArenaLike,
    owner : String,
  ) : Adamas::Compiler::Frontend::DefNode?
    old_class = @current_class
    @current_class = owner
    begin
      source_recovered_def_for(node, arena)
    ensure
      @current_class = old_class
    end
  end

  def __test_macro_generated_ivar_param_entries(
    node : Adamas::Compiler::Frontend::DefNode,
    arena : Adamas::Compiler::Frontend::ArenaLike,
    expected_method_name : String,
  ) : Array(Tuple(String, String?))?
    macro_generated_ivar_param_entries(node, arena, expected_method_name)
  end

  def __test_remember_macro_generated_parameter_sources(
    expr_id : Adamas::Compiler::Frontend::ExprId,
    arena : Adamas::Compiler::Frontend::ArenaLike,
    source : String,
  ) : Nil
    remember_macro_generated_parameter_sources(expr_id, arena, source)
  end

  def __test_generic_owner_info_map(owner : String) : Hash(String, String)?
    generic_owner_info(owner).try(&.map)
  end

  def __test_lower_function_if_needed(name : String) : Nil
    lower_function_if_needed(name)
  end

  def __test_lower_inherited_method_specialization(
    source_name : String,
    materialized_owner : String,
    target_name : String,
    call_arg_types : Array(Adamas::HIR::TypeRef),
  ) : Nil
    source_def = @function_defs[source_name]
    owner_info = @class_info[materialized_owner]
    old_override = @current_namespace_override
    @current_namespace_override = method_owner_from_name(source_name)
    begin
      lower_method(
        materialized_owner,
        owner_info,
        source_def,
        call_arg_types,
        full_name_override: target_name,
      )
    ensure
      @current_namespace_override = old_override
    end
  end

  def __test_resolve_generic_return_type(
    owner : String,
    method_name : String,
    call_arg_count : Int32,
  ) : Adamas::HIR::TypeRef?
    receiver_type = type_ref_for_name(owner)
    base_name = "#{owner}##{method_name}"
    resolve_return_type_from_def(
      base_name,
      base_name,
      receiver_type == Adamas::HIR::TypeRef::VOID ? nil : receiver_type,
      call_arg_count,
    )
  end

  def __test_concrete_union_dispatch_return_type(
    function_name : String,
    receiver_name : String,
    method_name : String,
    call_arg_count : Int32,
  ) : Adamas::HIR::TypeRef
    concrete_union_dispatch_return_type(
      function_name,
      type_ref_for_name(receiver_name),
      method_name,
      call_arg_count,
    )
  end

  def __test_set_lazy_module_methods(value : Bool) : Nil
    @lazy_module_methods = value
  end

  def __test_process_pending_lower_functions : Nil
    process_pending_lower_functions
  end

  def __test_record_lowering_demand(
    name : String,
    source : String,
    arg_types : Array(Adamas::HIR::TypeRef),
    arg_literals : Array(Bool)? = nil,
    enum_names : Array(String?)? = nil,
  ) : Nil
    remember_callsite_arg_types(name, arg_types, arg_literals, enum_names)
    enqueue_pending_function(name, source)
  end

  def __test_lowering_demand_ledger_events : Array(String)
    @lowering_demand_ledger_events.try(&.dup) || [] of String
  end

  def __test_lowering_demand_ledger_full? : Bool
    @lowering_demand_ledger_full
  end

  def __test_repair_receiver_bound_call_targets : Nil
    repair_receiver_bound_call_targets
  end

  # Test-only bridge for the bounded missing-call sweep. The production method
  # intentionally reads its budget from the environment; keep the mutation
  # scoped to this call so focused specs can exercise the exact quota path
  # without leaking state into neighboring examples.
  def __test_lower_missing_call_targets_with_budget(budget : Int32) : Nil
    previous = ENV["ADAMAS_MISSING_BUDGET"]?
    ENV["ADAMAS_MISSING_BUDGET"] = budget.to_s
    lower_missing_call_targets
  ensure
    if previous
      ENV["ADAMAS_MISSING_BUDGET"] = previous
    else
      ENV.delete("ADAMAS_MISSING_BUDGET")
    end
  end

  def __test_lower_receiver_repair_target_with_fallback(
    exact_target : String,
    fallback_base : String,
  ) : {Bool, Bool}
    exact_targets = Set(String).new
    fallback_requests = [] of ReceiverRepairFallback
    fallback_seen = Set(ReceiverRepairFallback).new
    record_receiver_repair_target(
      exact_targets,
      fallback_requests,
      fallback_seen,
      exact_target,
      fallback_base,
    )
    lower_receiver_repair_targets(exact_targets, fallback_requests)
    {
      @module.has_function_with_body?(exact_target),
      @module.has_function_with_body?(fallback_base),
    }
  end

  def __test_lower_receiver_repair_targets_with_fallbacks(
    requests : Array({String, String, Array(Adamas::HIR::TypeRef)}),
  ) : Nil
    exact_targets = Set(String).new
    fallback_requests = [] of ReceiverRepairFallback
    fallback_seen = Set(ReceiverRepairFallback).new
    requests.each do |exact_target, fallback_base, arg_types|
      record_receiver_repair_target(
        exact_targets,
        fallback_requests,
        fallback_seen,
        exact_target,
        fallback_base,
        "",
        arg_types,
      )
    end
    lower_receiver_repair_targets(exact_targets, fallback_requests)
  end

  def __test_receiver_repair_strict_target_expected(
    exact_target : String,
    fallback_base : String,
    owner : String,
    arg_types : Array(Adamas::HIR::TypeRef),
  ) : Bool
    receiver_repair_strict_target_expected?(ReceiverRepairFallback.new(
      exact_target,
      fallback_base,
      owner,
      arg_types,
      false,
      false,
      false,
      "",
      UInt32::MAX,
      false,
      nil,
    ))
  end

  def __test_get_function_return_type(name : String) : Adamas::HIR::TypeRef
    get_function_return_type(name)
  end

  def __test_get_function_return_type_for_call(name : String, arg_count : Int32) : Adamas::HIR::TypeRef
    get_function_return_type(name, arg_count)
  end

  def __test_canonical_typed_hash_return_contract(
    name : String,
    receiver_name : String,
  ) : Adamas::HIR::TypeRef?
    canonical_typed_hash_return_contract(
      name,
      strip_type_suffix(name),
      1,
      type_ref_for_name(receiver_name),
    )
  end

  def __test_enum_return_name_for(name : String) : String?
    enum_return_name_for(name)
  end

  def __test_force_ivar_type(owner : String, ivar_name : String, type_name : String) : Nil
    info = @class_info[owner]?
    raise "test class not found: #{owner}" unless info
    type_ref = type_ref_for_name(type_name)
    raise "test type not found: #{type_name}" if type_ref == Adamas::HIR::TypeRef::VOID
    index = info.not_nil!.ivars.index { |ivar| ivar.name == ivar_name }
    raise "test ivar not found: #{owner}##{ivar_name}" unless index
    existing = info.not_nil!.ivars[index.not_nil!]
    info.not_nil!.ivars[index.not_nil!] = Adamas::HIR::IVarInfo.new(
      existing.name,
      type_ref,
      existing.offset,
      existing.default_expr_id,
      existing.default_arena,
    )
  end

  def __test_enum_metadata_target_compatible(type_name : String, enum_name : String) : Bool
    enum_metadata_target_compatible?(type_ref_for_name(type_name), enum_name)
  end

  def __test_resolve_union_method_call(
    type_name : String,
    method_name : String,
    arg_types : Array(Adamas::HIR::TypeRef) = [] of Adamas::HIR::TypeRef,
    has_block_call : Bool = false,
  ) : String?
    resolve_union_method_call(type_name, method_name, arg_types, has_block_call)
  end

  def __test_register_function_type(name : String, return_type : Adamas::HIR::TypeRef) : Nil
    register_function_type(name, return_type)
  end

  def __test_register_class_with_name(node : Adamas::Compiler::Frontend::ClassNode, name : String) : Nil
    register_class_with_name(node, name)
  end

  def __test_register_enum_with_name(node : Adamas::Compiler::Frontend::EnumNode, name : String) : Nil
    register_enum_with_name(node, name)
  end

  def __test_type_ref_for_name(name : String) : Adamas::HIR::TypeRef
    type_ref_for_name(name)
  end

  def __test_annotation_type_ref(name : String, owner_name : String? = nil) : Adamas::HIR::TypeRef
    annotation_type_ref(name, owner_name)
  end

  def __test_subclasses(name : String) : Array(String)
    collect_subclasses_cached(name)
  end

  def __test_cached_union_type_ref_stale(type_ref : Adamas::HIR::TypeRef, name : String) : Bool
    cached_union_type_ref_stale?(type_ref, name)
  end

  def __test_get_type_name_from_ref(type_ref : Adamas::HIR::TypeRef) : String
    get_type_name_from_ref(type_ref)
  end

  def __test_infer_type_name(
    expr_id : Adamas::Compiler::Frontend::ExprId,
    self_type_name : String?,
  ) : String?
    infer_type_from_expr(expr_id, self_type_name).try do |type_ref|
      get_type_name_from_ref(type_ref)
    end
  end

  def __test_infer_self_type_name : String?
    @infer_self_type_name
  end

  def __test_local_inference_after_dependency_update(
    body : Array(Adamas::Compiler::Frontend::ExprId),
    name : String,
    dependency : String,
  ) : {String?, String?}
    old_locals = @current_typeof_locals
    old_local_names = @current_typeof_local_names
    @current_typeof_locals = {} of String => Adamas::HIR::TypeRef
    @current_typeof_local_names = {} of String => String
    @infer_type_cache_version += 1
    begin
      before = infer_local_type_from_body(body, name, nil)
      update_typeof_local(dependency, Adamas::HIR::TypeRef::INT32)
      after = infer_local_type_from_body(body, name, nil)
      {
        before.try { |type_ref| get_type_name_from_ref(type_ref) },
        after.try { |type_ref| get_type_name_from_ref(type_ref) },
      }
    ensure
      @current_typeof_locals = old_locals
      @current_typeof_local_names = old_local_names
      @infer_type_cache_version += 1
    end
  end

  def __test_block_param_types_after_stale_yield_cache(
    function_name : String,
    receiver_name : String,
    arg_type_names : Array(String),
  ) : Array(String)?
    resolved_function_name = function_name
    func_def = @function_defs[resolved_function_name]?
    unless func_def
      method_tail = function_name.rindex('#').try { |index| function_name[index..] } || function_name
      requested_owner = function_name.rindex('#').try { |index| function_name[0...index] } || ""
      requested_owner_base = strip_generic_args(requested_owner)
      @function_defs.each do |candidate_name, candidate_def|
        if candidate_name.includes?(requested_owner_base) &&
           candidate_name.includes?(method_tail) &&
           method_suffix(candidate_name).try { |suffix| suffix_has_block_flag?(suffix) }
          resolved_function_name = candidate_name
          func_def = candidate_def
          break
        end
      end
    end
    return nil unless func_def
    body = func_def.not_nil!.body
    return nil unless body
    def_arena = @function_def_arenas[resolved_function_name]? || @arena

    old_arena = @arena
    old_locals = @current_typeof_locals
    old_local_names = @current_typeof_local_names
    @arena = def_arena
    @current_typeof_locals = {} of String => Adamas::HIR::TypeRef
    @current_typeof_local_names = {} of String => String
    @infer_type_cache_version += 1
    begin
      yield_args = [] of Array(Adamas::Compiler::Frontend::ExprId)
      collect_yield_arg_lists(body, yield_args)
      first_yield_arg = yield_args.first?.try(&.first?)
      return nil unless first_yield_arg

      # Simulate an earlier inference pass that saw the yield expression before
      # its nested block parameter had a type and cached VOID for that AST node.
      infer_type_from_expr(first_yield_arg, receiver_name)

      receiver_type = type_ref_for_name(receiver_name)
      arg_types = arg_type_names.map { |name| type_ref_for_name(name) }
      param_map = type_param_map_for_receiver_type(receiver_type)
      inferred = infer_yield_param_types_from_body(
        func_def.not_nil!,
        resolved_function_name,
        strip_type_suffix(resolved_function_name),
        receiver_type,
        param_map,
        arg_types,
      )
      inferred.try(&.map { |type_ref| get_type_name_from_ref(type_ref) })
    ensure
      @arena = old_arena
      @current_typeof_locals = old_locals
      @current_typeof_local_names = old_local_names
      @infer_type_cache_version += 1
    end
  end

  def __test_block_param_types_for_call(
    base_method_name : String,
    mangled_method_name : String,
    receiver_name : String,
    arg_type_names : Array(String),
  ) : Array(String)?
    receiver_type = type_ref_for_name(receiver_name)
    arg_types = arg_type_names.map { |name| type_ref_for_name(name) }
    block_param_types_for_call(
      base_method_name,
      mangled_method_name,
      receiver_type,
      arg_types,
    ).try(&.map { |type_ref| get_type_name_from_ref(type_ref) })
  end

  def __test_block_param_types_for_call_in_context(
    base_method_name : String,
    mangled_method_name : String,
    current_name : String,
    ambient_type_params : Hash(String, String),
    arg_type_names : Array(String),
  ) : Array(String)?
    old_class = @current_class
    old_method = @current_method
    old_override = @current_namespace_override
    @current_class = current_name
    @current_method = "#{current_name}#each"
    @current_namespace_override = nil
    arg_types = arg_type_names.map { |name| type_ref_for_name(name) }
    begin
      with_type_param_map(ambient_type_params) do
        block_param_types_for_call(
          base_method_name,
          mangled_method_name,
          Adamas::HIR::TypeRef::VOID,
          arg_types,
        ).try(&.map { |type_ref| get_type_name_from_ref(type_ref) })
      end
    ensure
      @current_class = old_class
      @current_method = old_method
      @current_namespace_override = old_override
    end
  end

  def __test_non_nil_type_name_without_legacy_descriptor(union_name : String) : String?
    union_type = type_ref_for_name(union_name)
    @union_descriptors.delete(hir_to_mir_type_ref(union_type))
    narrowed = non_nil_type_for_union(union_type)
    narrowed ? generic_param_type_name_from_ref(narrowed) : nil
  end

  def __test_exact_union_variant_name(
    full_name : String,
    type_ref : Adamas::MIR::TypeRef = Adamas::MIR::TypeRef::VOID,
  ) : String?
    variant = Adamas::MIR::UnionVariantDescriptor.new(1, type_ref, full_name, 8, 8, nil)
    exact = exact_hir_type_ref_for_union_variant(variant)
    exact == Adamas::HIR::TypeRef::VOID ? nil : generic_param_type_name_from_ref(exact)
  end

  def __test_method_resolution_cache_key(
    call_has_named_args : Bool,
    named_args_count : Int32,
    named_arg_names : Array(String)? = nil,
  ) : UInt64
    method_resolution_cache_key(
      Adamas::HIR::TypeRef::INT32,
      "probe",
      [Adamas::HIR::TypeRef::INT32],
      false,
      false,
      true,
      false,
      call_has_named_args,
      named_args_count,
      named_arg_names_hash(canonical_named_arg_names(named_arg_names)),
      "DispatchRoot::Mutable(Int32)",
    )
  end

  def __test_select_missing_call_target_batch(
    missing : Array(String),
    budget : Int32,
  ) : {Array(String), Bool}
    select_missing_call_target_batch(missing, budget)
  end

  def __test_missing_incremental_refresh_segments(
    cached : Hash(UInt64, Array(String)),
    order : Array(UInt64),
    current : Hash(UInt64, Array(String)),
  ) : {Array(Array(String)), Int32}
    missing_incremental_refresh_segments(cached, order, current)
  end

  def __test_missing_incremental_flatten_segments(
    segments : Array(Array(String)),
  ) : Array(String)
    missing_incremental_flatten_segments(segments)
  end

  def __test_missing_incremental_target_certificate(
    name : String,
    queued_names : Array(String),
  ) : {Bool, String, Bool}
    queued = Set(String).new(queued_names.size)
    queued_names.each { |queued_name| queued.add(queued_name) }
    certificate = missing_incremental_target_certificate(name, queued)
    {
      certificate.body_present,
      certificate.state.to_s,
      certificate.queued,
    }
  end

  def __test_set_missing_incremental_target_state(
    name : String,
    state : String,
  ) : Nil
    @function_lowering_states[name] = case state
                                      when "pending"
                                        FunctionLoweringState::Pending
                                      when "in_progress"
                                        FunctionLoweringState::InProgress
                                      when "completed"
                                        FunctionLoweringState::Completed
                                      else
                                        FunctionLoweringState::NotStarted
                                      end
  end

  def __test_module_virtual_fanout_shape_key(
    receiver_name : String,
    arg_types : Array(Adamas::HIR::TypeRef),
  ) : String
    virtual_target_shape_key(receiver_name, "probe", arg_types, false, false)
  end

  def __test_module_fanout_owner_shape_compatible?(
    owner_name : String,
    receiver_shape : String,
  ) : Bool
    module_fanout_owner_shape_compatible?(owner_name, receiver_shape)
  end

  def __test_class_include_instantiations(owner_name : String) : Array(String)
    @class_include_instantiations[owner_name]? || [] of String
  end

  def __test_module_shape_has_unbound_params?(type_name : String) : Bool
    module_shape_has_unbound_params?(type_name)
  end

  def __test_module_fanout_owner_plan(
    module_base : String,
    receiver_shape : String,
  ) : Array(String)
    module_fanout_owner_plan(
      module_base,
      receiver_shape,
      @module_includers[module_base]?,
    )[0]
  end

  def __test_record_class_include_instantiation(
    owner_name : String,
    instantiation : String,
  ) : Nil
    record_class_include_instantiation(owner_name, instantiation)
  end

  def __test_module_virtual_target_deferred_then_retry(
    owner_name : String,
    method_name : String,
    arg_types : Array(Adamas::HIR::TypeRef),
  ) : {Bool, Bool, Bool}
    base_name = "#{owner_name}##{method_name}"
    resolved = lookup_function_def_for_call(
      base_name,
      arg_types.size,
      false,
      arg_types,
      false,
    )
    raise "missing virtual target fixture: #{base_name}" unless resolved

    resolved_name = resolved[0]
    resolved_base = strip_type_suffix(resolved_name)
    target_names = [resolved_name, resolved_base].uniq
    target_names.each do |name|
      @module.remove_function(name)
      @function_lowering_states.delete(name)
      @pending_function_queue.delete(name)
    end

    saved_depth = @lowering_depth
    begin
      @lowering_depth = @lowering_depth_limit + 1
      first_complete = lower_virtual_target_resolved(
        owner_name,
        method_name,
        arg_types,
        false,
        false,
      )

      target_names.each do |name|
        @function_lowering_states.delete(name)
        @pending_function_queue.delete(name)
      end
      @lowering_depth = 0
      second_complete = lower_virtual_target_resolved(
        owner_name,
        method_name,
        arg_types,
        false,
        false,
      )

      body_available = target_names.any? do |name|
        @module.has_function_with_body?(name)
      end
      {first_complete, second_complete, body_available}
    ensure
      @lowering_depth = saved_depth
    end
  end

  def __test_fanout_pending_survives_def_replacement(
    def_name : String,
    replacement_def_name : String,
    method_name : String,
  ) : Bool
    original_key = @function_defs.keys.find do |name|
      name == def_name || name.starts_with?("#{def_name}$")
    end || raise "missing original def fixture: #{def_name}"
    replacement_key = @function_defs.keys.find do |name|
      name == replacement_def_name || name.starts_with?("#{replacement_def_name}$")
    end
    replacement = replacement_key.try { |name| @function_defs[name]? } ||
                  raise "missing replacement def fixture: #{replacement_def_name}"

    fanout_key = "test-fanout\u{1f}#{method_name}"
    pending_target = "DeferredOwner##{method_name}$Int32"
    (@module_virtual_fanout_keys_by_method[method_name] ||= Set(String).new) << fanout_key
    @module_virtual_fanout_pending_targets[fanout_key] = {
      pending_target => ModuleVirtualFanoutPendingTarget.new(
        pending_target,
        "DeferredOwner",
        method_name,
        [Adamas::HIR::TypeRef::INT32],
        false,
        false,
      ),
    }

    set_function_def_entry(original_key, replacement, record_current_arena: false)

    @module_virtual_fanout_pending_targets[fanout_key]?
      .try(&.has_key?(pending_target)) || false
  end

  def __test_terminal_fanout_discard_invalidates_result(
    method_name : String,
  ) : {Int32, Int32, Bool, Bool, Bool}
    fanout_key = "terminal-fanout\u{1f}#{method_name}"
    pending_target = "NeverMaterialized##{method_name}$Int32"
    (@module_virtual_fanout_keys_by_method[method_name] ||= Set(String).new) << fanout_key
    @module_virtual_fanout_versions[fanout_key] =
      module_virtual_fanout_registry_version("NeverMaterialized")
    @module_virtual_fanout_pending_targets[fanout_key] = {
      pending_target => ModuleVirtualFanoutPendingTarget.new(
        pending_target,
        "NeverMaterialized",
        method_name,
        [Adamas::HIR::TypeRef::INT32],
        false,
        false,
      ),
    }

    discarded, unresolved = discard_terminal_module_virtual_fanout_pending_targets
    {
      discarded,
      unresolved,
      @module_virtual_fanout_pending_targets.has_key?(fanout_key),
      @module_virtual_fanout_versions.has_key?(fanout_key),
      @module_virtual_fanout_keys_by_method[method_name]?.try(&.includes?(fanout_key)) || false,
    }
  end

  def __test_unproductive_fanout_retry_fixed_point(
    method_name : String,
    state_after_retry : String? = nil,
  ) : {Int32, Bool}
    fanout_key = "fixed-point-fanout\u{1f}#{method_name}"
    pending_target = "NeverMaterialized##{method_name}$Int32"
    @module_virtual_fanout_pending_targets[fanout_key] = {
      pending_target => ModuleVirtualFanoutPendingTarget.new(
        pending_target,
        "NeverMaterialized",
        method_name,
        [Adamas::HIR::TypeRef::INT32],
        false,
        false,
      ),
    }

    snapshot = final_missing_fixed_point_snapshot
    attempts = repair_module_virtual_fanout_pending_targets
    case state_after_retry
    when "pending"
      set_function_state(pending_target, FunctionLoweringState::Pending)
    when "cycle"
      set_function_state(pending_target, FunctionLoweringState::Pending)
      clear_function_state(pending_target)
    end
    {
      attempts,
      final_missing_fixed_point_reached?(snapshot),
    }
  end

  def __test_final_missing_fixed_point_snapshot
    final_missing_fixed_point_snapshot
  end

  def __test_final_missing_fixed_point_reached?(snapshot) : Bool
    final_missing_fixed_point_reached?(snapshot)
  end

  def __test_final_missing_should_stop?(snapshot, pass_count : Int32) : Bool
    final_missing_should_stop?(snapshot, pass_count)
  end

  def __test_terminal_fanout_preserves_concrete_bodyless_target(
    def_name : String,
    method_name : String,
  ) : {Int32, Int32, Bool, Bool}
    concrete_def_name = @function_defs.keys.find do |name|
      name == def_name || name.starts_with?("#{def_name}$")
    end || raise "missing concrete def fixture: #{def_name}"

    # Typed DefNodes are registered under their concrete suffix (for example,
    # `ConcreteTerminalOwner#probe$Int32`). Keep that exact symbol as the
    # pending target; remangling it would produce a distinct invalid key.
    target_name = concrete_def_name
    remove_hir_function(target_name)
    @function_lowering_states.delete(target_name)

    owner = method_owner(concrete_def_name)
    fanout_key = "concrete-terminal-fanout\u{1f}#{method_name}"
    (@module_virtual_fanout_keys_by_method[method_name] ||= Set(String).new) << fanout_key
    @module_virtual_fanout_versions[fanout_key] =
      module_virtual_fanout_registry_version(owner)
    @module_virtual_fanout_pending_targets[fanout_key] = {
      target_name => ModuleVirtualFanoutPendingTarget.new(
        target_name,
        owner,
        method_name,
        [Adamas::HIR::TypeRef::INT32],
        false,
        false,
      ),
    }

    discarded, unresolved = discard_terminal_module_virtual_fanout_pending_targets
    {
      discarded,
      unresolved,
      @module_virtual_fanout_pending_targets[fanout_key]?
        .try(&.has_key?(target_name)) || false,
      @module_virtual_fanout_versions.has_key?(fanout_key),
    }
  end

  def __test_union_variant_id(union_type : Adamas::HIR::TypeRef, variant_type : Adamas::HIR::TypeRef) : Int32
    get_union_variant_id(union_type, variant_type)
  end

  def __test_array_index_union_variant_ids(type_name : String) : Tuple(Int32, Int32)
    array_index_union_variant_ids(type_ref_for_name(type_name))
  end

  def __test_case_subject_cached_method_result?(
    ctx : Adamas::HIR::LoweringContext,
    value_id : Adamas::HIR::ValueId,
    source_name : String,
  ) : Bool
    case_subject_cached_method_result?(ctx, value_id, source_name)
  end

  def __test_bump_module_defs_cache_version : Nil
    bump_module_defs_cache_version
  end

  def __test_defined_instance_method_scan_cache_body_count(class_name : String) : Int32
    body_ids = Set(UInt64).new
    @defined_method_full_names_cache.each_key do |key|
      body_ids << key[1] if key[0] == class_name
    end
    body_ids.size
  end

  def __test_defined_instance_method_scan_cache_arena_count(
    class_name : String,
    body : Array(Adamas::Compiler::Frontend::ExprId),
  ) : Int32
    body_id = body.object_id
    count = 0
    @defined_method_full_names_cache.each_key do |key|
      count += 1 if key[0] == class_name && key[1] == body_id
    end
    count
  end

  def __test_collect_defined_instance_method_full_names(
    class_name : String,
    body : Array(Adamas::Compiler::Frontend::ExprId),
    arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Set(String)
    collect_defined_instance_method_full_names(class_name, body, arena)
  end

  def __test_collect_defined_class_method_full_names(
    class_name : String,
    body : Array(Adamas::Compiler::Frontend::ExprId),
    arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Set(String)
    collect_defined_class_method_full_names(class_name, body, arena)
  end

  def __test_function_def_names(prefix : String = "") : Array(String)
    @function_defs.keys.select { |name| prefix.empty? || name.starts_with?(prefix) }
  end

  def __test_seeded_yield_cache_result(function_name : String, cached_value : Bool) : Bool
    node = @function_defs[function_name]? || raise "test function not found: #{function_name}"
    arena = @function_def_arenas[function_name]? || @arena
    resolved_arena = arena_fits_def?(arena, node) ? arena : resolve_arena_for_def(node, arena)
    cache_key = def_contains_yield_cache_key(node, resolved_arena)
    had_cached_value = @yield_check_cache.has_key?(cache_key)
    previous_value = @yield_check_cache[cache_key]?
    @yield_check_cache[cache_key] = cached_value
    begin
      def_contains_yield?(node, arena)
    ensure
      if had_cached_value
        @yield_check_cache[cache_key] = previous_value.not_nil!
      else
        @yield_check_cache.delete(cache_key)
      end
    end
  end

  def __test_macro_text_contains_yield(text : String) : Bool
    macro_text_contains_yield?(text)
  end

  def __test_function_param_annotations(name : String) : Array(String?)
    node = @function_defs[name]?
    return [] of String? unless node
    params = node.params
    return [] of String? unless params
    params.map do |param|
      param.type_annotation.try { |slice| String.new(slice) }
    end
  end

  def __test_function_param_identity(name : String) : Array(Tuple(String?, String?, String?, Bool, Bool, Bool))
    node = @function_defs[name]?
    return [] of Tuple(String?, String?, String?, Bool, Bool, Bool) unless node
    params = node.params
    return [] of Tuple(String?, String?, String?, Bool, Bool, Bool) unless params
    params.map do |param|
      {
        param.name.try { |slice| String.new(slice) },
        param.external_name.try { |slice| String.new(slice) },
        param.type_annotation.try { |slice| String.new(slice) },
        param.is_instance_var,
        param.is_splat,
        param.is_block,
      }
    end
  end

  def __test_function_param_default_presence(name : String) : Array(Bool)
    node = @function_defs[name]?
    return [] of Bool unless node
    params = node.params
    return [] of Bool unless params
    params.map { |param| !param.default_value.nil? }
  end

  def __test_register_concrete_class(
    node : Adamas::Compiler::Frontend::ClassNode,
    class_name : String,
    is_struct : Bool = false,
  ) : Nil
    register_concrete_class(node, class_name, is_struct)
  end

  def __test_monomorphize_generic_class(base_name : String, type_args : Array(String), specialized_name : String) : Nil
    monomorphize_generic_class(base_name, type_args, specialized_name)
  end

  def __test_generic_reopening_count(base_name : String) : Int32
    @generic_reopenings[base_name]?.try(&.size) || 0
  end

  def __test_module_def_count(name : String) : Int32
    @module_defs[name]?.try(&.size) || 0
  end

  def __test_module_defs_cache_version : Int32
    @module_defs_cache_version
  end

  def __test_has_module_def_recursive?(module_name : String, method_name : String) : Bool
    !find_module_def_recursive(
      module_name,
      method_name,
      0,
      Set(String).new,
    ).nil?
  end

  def __test_union_type_for_values(
    left_type : Adamas::HIR::TypeRef,
    right_type : Adamas::HIR::TypeRef,
  ) : Adamas::HIR::TypeRef
    union_type_for_values(left_type, right_type)
  end

  def __test_union_type_for_value_set(
    types : Array(Adamas::HIR::TypeRef),
  ) : Adamas::HIR::TypeRef?
    union_type_for_value_set(types)
  end

  def __test_repair_stale_call_return_types : Nil
    repair_stale_call_return_types
  end

  def __test_reset_lowering_state(name : String) : Nil
    @function_lowering_states.delete(name)
    @pending_function_queue.delete(name)
  end

  def __test_mark_lowering_completed(name : String) : Nil
    @function_lowering_states[name] = FunctionLoweringState::Completed
  end

  def __test_function_lowering_completed?(name : String) : Bool
    function_state(name).completed?
  end

  def __test_lower_allocator_initializer_body(
    class_name : String,
    init_name : String,
    callsite_types : Array(Adamas::HIR::TypeRef),
  ) : Nil
    info = @class_info[class_name]
    lower_allocator_initializer_body(
      class_name,
      info,
      "#{class_name}#initialize",
      init_name,
      callsite_types,
    )
  end

  # Re-enter the synthesized allocator path after its body and the selected
  # initializer body have been removed. This exercises the late
  # rematerialization route rather than the direct resolver helper above.
  def __test_regenerate_allocator(
    class_name : String,
    call_arg_types : Array(Adamas::HIR::TypeRef),
  ) : Nil
    generate_allocator(class_name, @class_info[class_name], call_arg_types)
  end

  def __test_replace_initializer_params(
    class_name : String,
    params : Array({String, Adamas::HIR::TypeRef}),
  ) : Nil
    @init_params[class_name] = params
  end

  def __test_initializer_params(class_name : String) : Array({String, String})
    params = @init_params[class_name]? || [] of {String, Adamas::HIR::TypeRef}
    params.map do |name, type_ref|
      {name, get_type_name_from_ref(type_ref)}
    end
  end

  def __test_refine_captured_initializer_proc_type(
    class_name : String,
    proc_type_name : String,
    observed_return_type_name : String,
  ) : Nil
    refine_captured_initializer_proc_type(
      class_name,
      type_ref_for_name(proc_type_name),
      type_ref_for_name(observed_return_type_name),
    )
  end

  def __test_allocator_initializer_def_name(
    class_name : String,
    init_name : String,
    callsite_types : Array(Adamas::HIR::TypeRef),
    call_has_block : Bool = false,
    call_has_named_args : Bool = false,
    call_named_arg_names : Array(String)? = nil,
  ) : String?
    resolved = allocator_initializer_def_for(
      "#{class_name}#initialize",
      init_name,
      callsite_types,
      call_has_block,
      call_has_named_args,
      call_named_arg_names,
    )
    resolved.try(&.[0])
  end

  def __test_allocator_initializer_direct_shape_compatible?(
    name : String,
    callsite_types : Array(Adamas::HIR::TypeRef),
    call_has_block : Bool = false,
    call_has_named_args : Bool = false,
    call_named_arg_names : Array(String)? = nil,
  ) : Bool
    def_node = @function_defs[name]?
    return false unless def_node
    function_def_accepts_call_shape?(
      name,
      def_node,
      callsite_types,
      call_has_block,
      call_has_named_args,
      call_named_arg_names,
    )
  end

  def __test_allocator_initializer_def_name_for_base(
    init_base_name : String,
    init_name : String,
    callsite_types : Array(Adamas::HIR::TypeRef),
    call_has_block : Bool = false,
    call_has_named_args : Bool = false,
    call_named_arg_names : Array(String)? = nil,
  ) : String?
    resolved = allocator_initializer_def_for(
      init_base_name,
      init_name,
      callsite_types,
      call_has_block,
      call_has_named_args,
      call_named_arg_names,
    )
    resolved.try(&.[0])
  end

  def __test_allocator_unique_positional_def_name_for_base(
    init_base_name : String,
    requested_name : String,
    callsite_types : Array(Adamas::HIR::TypeRef),
    call_has_block : Bool = false,
  ) : String?
    resolved = allocator_unique_positional_def_for(
      init_base_name,
      requested_name,
      callsite_types,
      call_has_block,
    )
    resolved.try(&.[0])
  end

  # Deliberately invalidate a DefNode's typed annotation and the derived
  # resolver caches. This models the late self-host metadata loss that makes
  # normal type compatibility miss while preserving source arity/shape.
  def __test_corrupt_function_def_param_type(
    name : String,
    replacement_type : String,
  ) : Nil
    def_node = @function_defs[name]?
    return unless def_node
    params = def_node.params
    return unless params
    replacement = [] of Adamas::Compiler::Frontend::Parameter
    params.each do |param|
      if param.is_block || param.is_splat || param.is_double_splat || param.type_annotation.nil?
        replacement << param
      else
        replacement << Adamas::Compiler::Frontend::Parameter.new(
          param.name,
          param.external_name,
          replacement_type.to_slice,
          param.default_value,
          param.span,
          param.name_span,
          param.external_name_span,
          nil,
          param.default_span,
          param.is_splat,
          param.is_double_splat,
          param.is_block,
          param.is_instance_var,
        )
      end
    end
    params.clear
    params.concat(replacement)
    @function_param_infos.delete(name)
    @function_param_stats.delete(name)
    @function_param_infos_by_def_id.delete(def_node.object_id.to_u64)
  end

  def __test_repair_missing_concrete_virtual_targets : Int32
    repair_missing_concrete_virtual_targets
  end

  def __test_mark_live_type(name : String) : Nil
    mark_live_type(name)
  end

  def __test_scan_hir_function_for_live_types(func : Adamas::HIR::Function) : Bool
    scan_hir_function_for_live_types(func)
  end

  def __test_set_lazy_rta_active(value : Bool) : Nil
    @lazy_rta_active = value
  end

  def __test_record_virtual_target(parent_name : String, method_name : String, arg_types : Array(Adamas::HIR::TypeRef)) : Nil
    record_virtual_target(parent_name, method_name, arg_types, false, false)
  end

  def __test_record_virtual_target_inside_lowering(parent_name : String, method_name : String, arg_types : Array(Adamas::HIR::TypeRef)) : Nil
    old_depth = @lowering_depth
    @lowering_depth = @lowering_depth_limit + 1
    record_virtual_target(parent_name, method_name, arg_types, false, false)
  ensure
    @lowering_depth = old_depth.as(Int32)
  end

  def __test_collect_subclasses_cached(parent_name : String) : Array(String)
    collect_subclasses_cached(parent_name)
  end

  def __test_replay_virtual_targets_for_registered_class(class_name : String) : Nil
    replay_virtual_targets_for_registered_class(class_name)
  end

  def __test_concrete_value_virtual_repair_owner?(owner : String) : Bool
    concrete_value_virtual_repair_owner?(owner)
  end

  def __test_register_virtual_repair_class_info(name : String, type_ref : Adamas::HIR::TypeRef, is_struct : Bool) : Nil
    @class_info[name] = Adamas::HIR::ClassInfo.new(
      name,
      type_ref,
      [] of Adamas::HIR::IVarInfo,
      [] of Adamas::HIR::ClassVarInfo,
      0,
      is_struct,
      nil
    )
  end

  def __test_queue_pending_inside_lowering(name : String) : Nil
    old_depth = @lowering_depth
    @lowering_depth = @lowering_depth_limit + 1
    lower_function_if_needed(name)
  ensure
    @lowering_depth = old_depth.as(Int32)
  end

  def __test_rta_called_method?(name : String) : Bool
    @rta_called_methods.includes?(name)
  end

  def __test_rta_called_method_part?(name : String) : Bool
    @rta_called_method_parts.includes?(name)
  end

  def __test_pending_function?(name : String) : Bool
    @pending_function_queue.includes?(name)
  end

  def __test_pending_function_occurrences(name : String) : Int32
    @pending_function_queue.count(name)
  end

  def __test_remember_callsite_arg_types(name : String, arg_types : Array(Adamas::HIR::TypeRef), has_block : Bool = false) : Nil
    remember_callsite_arg_types(name, arg_types, has_block: has_block)
  end

  def __test_concrete_suffix_types_for_reselect?(suffix : String, observed_arity : Int32?) : Bool
    !concrete_suffix_types_for_reselect(suffix, observed_arity).nil?
  end

  def __test_repair_partial_untyped_call_types_from_history(
    lookup_name : String,
    node : Adamas::Compiler::Frontend::DefNode,
    call_types : Array(Adamas::HIR::TypeRef),
  ) : Array(Adamas::HIR::TypeRef)
    repair_partial_untyped_call_types_from_history(lookup_name, node, call_types)
  end

  def __test_missing_required_runtime_param_types?(
    node : Adamas::Compiler::Frontend::DefNode,
    call_types : Array(Adamas::HIR::TypeRef),
  ) : Bool
    missing_required_runtime_param_types?(node, call_types)
  end

  def __test_merge_call_arg_type_names_from_suffix(
    node : Adamas::Compiler::Frontend::DefNode,
    call_type_names : Array(String),
    suffix_type_names : Array(String),
  ) : Array(String)
    call_types = call_type_names.map { |name| type_ref_for_name(name) }
    suffix_types = suffix_type_names.map { |name| type_ref_for_name(name) }
    merge_call_arg_types_from_suffix_with_signature(call_types, suffix_types, node)
      .map { |type_ref| get_type_name_from_ref(type_ref) }
  end

  def __test_classvar_lazy_init_key?(key : String) : Bool
    @classvar_lazy_init_info.has_key?(key)
  end

  def __test_deferred_classvar_init_names : Array(String)
    @deferred_classvar_inits.compact_map do |entry|
      extract_deferred_classvar_name(entry.arena, entry.expr_id)
    end
  end

  def __test_sorted_deferred_constant_init_names : Array(String)
    sort_deferred_constant_inits!
    @deferred_constant_inits.map(&.name)
  end

  def __test_constant_literal_int_value(name : String) : Int64?
    value = @constant_literal_values[name]?
    return nil unless value.is_a?(Adamas::Compiler::Semantic::MacroNumberValue)
    raw = value.value
    raw.is_a?(Int64) ? raw : nil
  end
end

private def add_defined_scan_def(arena, name : String) : Adamas::Compiler::Frontend::ExprId
  arena.retain_source(name)
  arena.add_typed(Adamas::Compiler::Frontend::DefNode.new(
    Adamas::Compiler::Frontend::Span.zero,
    name.to_slice,
    nil,
    nil,
    [] of Adamas::Compiler::Frontend::ExprId,
  ))
end

describe "defined method scan caches" do
  it "preserves class, body, arena, and version identity through primitive keys" do
    first_arena = Adamas::Compiler::Frontend::AstArena.new
    virtual_arena = Adamas::Compiler::Frontend::VirtualArena.new
    page_arena = Adamas::Compiler::Frontend::PageArena.new
    converter = Adamas::HIR::AstToHir.new(first_arena)

    first_id = add_defined_scan_def(first_arena, "from_first_body")
    second_id = add_defined_scan_def(first_arena, "from_second_body")
    virtual_id = add_defined_scan_def(virtual_arena, "from_virtual_arena")
    page_id = page_arena.add_typed(Adamas::Compiler::Frontend::NilNode.new(
      Adamas::Compiler::Frontend::Span.zero,
    ))
    virtual_id.should eq(first_id)
    page_id.should eq(first_id)
    first_body = [first_id]
    second_body = [second_id]

    first_names = converter.__test_collect_defined_instance_method_full_names("IO::FileDescriptor", first_body, first_arena)
    first_names.should contain("IO::FileDescriptor#from_first_body")
    converter.__test_collect_defined_instance_method_full_names("IO::FileDescriptor", first_body, first_arena)
      .should eq(first_names)
    converter.__test_defined_instance_method_scan_cache_body_count("IO::FileDescriptor").should eq(1)
    converter.__test_defined_instance_method_scan_cache_arena_count("IO::FileDescriptor", first_body).should eq(1)

    converter.__test_collect_defined_instance_method_full_names("IO::FileDescriptor", second_body, first_arena)
      .should contain("IO::FileDescriptor#from_second_body")
    converter.__test_collect_defined_instance_method_full_names("IO::FileDescriptor", first_body, virtual_arena)
      .should contain("IO::FileDescriptor#from_virtual_arena")
    converter.__test_collect_defined_instance_method_full_names("IO::FileDescriptor", first_body, page_arena)
      .should be_empty
    converter.__test_defined_instance_method_scan_cache_body_count("IO::FileDescriptor").should eq(2)
    converter.__test_defined_instance_method_scan_cache_arena_count("IO::FileDescriptor", first_body).should eq(3)
    converter.__test_defined_instance_method_scan_cache_arena_count("IO::FileDescriptor", second_body).should eq(1)

    converter.__test_collect_defined_instance_method_full_names("IO", first_body, first_arena)
      .should contain("IO#from_first_body")
    converter.__test_defined_instance_method_scan_cache_body_count("IO").should eq(1)
    converter.__test_defined_instance_method_scan_cache_body_count("IO::FileDescriptor").should eq(2)

    converter.__test_bump_module_defs_cache_version
    converter.__test_defined_instance_method_scan_cache_body_count("IO::FileDescriptor").should eq(0)
  end

  it "retains distinct arena identities for exact cache hits" do
    arenas = Array(Adamas::Compiler::Frontend::AstArena).new(9) do |index|
      arena = Adamas::Compiler::Frontend::AstArena.new
      add_defined_scan_def(arena, "arena_#{index}")
      arena
    end
    converter = Adamas::HIR::AstToHir.new(arenas.first)
    body = [Adamas::Compiler::Frontend::ExprId.new(0)]

    arenas.each_with_index do |arena, index|
      converter.__test_collect_defined_instance_method_full_names("Bounded", body, arena)
        .should contain("Bounded#arena_#{index}")
    end
    converter.__test_defined_instance_method_scan_cache_arena_count("Bounded", body).should eq(9)

    converter.__test_collect_defined_instance_method_full_names("Bounded", body, arenas.first)
      .should contain("Bounded#arena_0")
    converter.__test_defined_instance_method_scan_cache_arena_count("Bounded", body).should eq(9)
  end

  it "retains distinct body identities for exact cache hits" do
    arena = Adamas::Compiler::Frontend::AstArena.new
    bodies = Array(Array(Adamas::Compiler::Frontend::ExprId)).new(9) do |index|
      [add_defined_scan_def(arena, "body_#{index}")]
    end
    converter = Adamas::HIR::AstToHir.new(arena)

    bodies.each_with_index do |body, index|
      converter.__test_collect_defined_instance_method_full_names("BoundedBodies", body, arena)
        .should contain("BoundedBodies#body_#{index}")
    end
    converter.__test_defined_instance_method_scan_cache_body_count("BoundedBodies").should eq(9)

    converter.__test_collect_defined_instance_method_full_names("BoundedBodies", bodies.first, arena)
      .should contain("BoundedBodies#body_0")
    converter.__test_defined_instance_method_scan_cache_body_count("BoundedBodies").should eq(9)
  end

  it "isolates instance and class scans, cache results, and versioned rescans" do
    arena, roots = parse(<<-CRYSTAL)
      class ScanTarget
        def foo
        end

        def self.bar
        end

        getter local_value : Int32
        class_getter shared_value : Int32
      end
    CRYSTAL
    class_id = roots.find { |expr_id| arena[expr_id].is_a?(Adamas::Compiler::Frontend::ClassNode) }
    class_id.should_not be_nil
    class_node = arena[class_id.not_nil!].as(Adamas::Compiler::Frontend::ClassNode)
    body = class_node.body.not_nil!
    converter = Adamas::HIR::AstToHir.new(arena)

    instance_names = converter.__test_collect_defined_instance_method_full_names("ScanTarget", body, arena)
    class_names = converter.__test_collect_defined_class_method_full_names("ScanTarget", body, arena)
    instance_names.should contain("ScanTarget#foo")
    instance_names.should_not contain("ScanTarget.bar")
    instance_names.should contain("ScanTarget#local_value")
    instance_names.should contain("ScanTarget#shared_value")
    class_names.should contain("ScanTarget.bar")
    class_names.should_not contain("ScanTarget#foo")
    class_names.should contain("ScanTarget.shared_value")
    class_names.should_not contain("ScanTarget.local_value")

    instance_names << "mutated caller copy"
    class_names << "mutated class caller copy"
    cached_names = converter.__test_collect_defined_instance_method_full_names("ScanTarget", body, arena)
    cached_names.should_not contain("mutated caller copy")
    converter.__test_collect_defined_class_method_full_names("ScanTarget", body, arena)
      .should_not contain("mutated class caller copy")

    new_name = "after_bump"
    arena.retain_source(new_name)
    new_def = Adamas::Compiler::Frontend::DefNode.new(
      Adamas::Compiler::Frontend::Span.zero,
      new_name.to_slice,
      nil,
      nil,
      [] of Adamas::Compiler::Frontend::ExprId,
    )
    body << arena.add_typed(new_def)
    converter.__test_collect_defined_instance_method_full_names("ScanTarget", body, arena)
      .should_not contain("ScanTarget#after_bump")

    converter.__test_bump_module_defs_cache_version
    converter.__test_collect_defined_instance_method_full_names("ScanTarget", body, arena)
      .should contain("ScanTarget#after_bump")
  end
end

describe "callsite splat suffix normalization" do
  it "removes only terminal splat flags without a regex path" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)

    converter.__test_strip_callsite_splat_suffix("Path.new$Path | String_Path | String_splat").should eq(
      "Path.new$Path | String_Path | String"
    )
    converter.__test_strip_callsite_splat_suffix("trace$Section_NamedTuple_double_splat").should eq(
      "trace$Section_NamedTuple"
    )
    converter.__test_strip_callsite_splat_suffix("Owner#splat_helper$String").should eq(
      "Owner#splat_helper$String"
    )
  end
end

describe "specialized function-name suffix stripping" do
  it "strips only the specialization suffix" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)

    converter.__test_strip_type_suffix("Enumerable#sum$Array_Int32").should eq("Enumerable#sum")
    converter.__test_strip_type_suffix("Enumerable#sum").should eq("Enumerable#sum")
  end
end

describe "compact method-name parsing" do
  it "preserves owner, method, separator, and unspecialized base" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)

    converter.__test_parse_method_name_compact("Outer::Owner#call$Int32").should eq(
      {"Outer::Owner", "call", '#', "Outer::Owner#call"}
    )
    converter.__test_parse_method_name_compact("Owner.build$String").should eq(
      {"Owner", "build", '.', "Owner.build"}
    )
    converter.__test_parse_method_name_compact("Outer.Inner#call$Int32").should eq(
      {"Outer.Inner", "call", '#', "Outer.Inner#call"}
    )
    converter.__test_parse_method_name_compact("Outer#Inner#call").should eq(
      {"Outer#Inner", "call", '#', "Outer#Inner#call"}
    )
    converter.__test_parse_method_name_compact("Owner#method.other$T").should eq(
      {"Owner", "method.other", '#', "Owner#method.other"}
    )
    converter.__test_parse_method_name_compact("Owner.one.two$T").should eq(
      {"Owner", "one.two", '.', "Owner.one.two"}
    )
    converter.__test_parse_method_name_compact("Owner$T#method").should eq(
      {"Owner$T#method", nil, nil, "Owner"}
    )
    converter.__test_parse_method_name_compact("call$Int32").should eq(
      {"call$Int32", nil, nil, "call"}
    )
    converter.__test_parse_method_name_compact("call").should eq(
      {"call", nil, nil, "call"}
    )
  end
end

describe "block shorthand parameter identity" do
  it "keeps as? provenance local to one lowering context" do
    arena = Adamas::Compiler::Frontend::AstArena.new
    converter = Adamas::HIR::AstToHir.new(arena)
    first = converter.module.create_function("__as_question_scope_first", Adamas::HIR::TypeRef::NIL)
    second = converter.module.create_function("__as_question_scope_second", Adamas::HIR::TypeRef::NIL)
    first_ctx = Adamas::HIR::LoweringContext.new(first, converter.module, arena)
    second_ctx = Adamas::HIR::LoweringContext.new(second, converter.module, arena)
    shared_value_id = 7_u32

    first_ctx.mark_as_question_result(shared_value_id)

    first_ctx.as_question_result?(shared_value_id).should be_true
    second_ctx.as_question_result?(shared_value_id).should be_false
  end

  it "narrows a nilable receiver from the descriptor sidecar when the legacy map entry is missing" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)

    converter
      .__test_non_nil_type_name_without_legacy_descriptor("Nil | Hash(String, String)")
      .should eq("Hash(String, String)")
  end

  it "preserves the full Proc identity when narrowing a nilable receiver" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)

    converter
      .__test_non_nil_type_name_without_legacy_descriptor("Nil | Proc(Int32, Nil | Exception, Nil)")
      .should eq("Proc(Int32, Nil | Exception, Nil)")
  end

  it "does not fabricate an unknown exact union variant" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)

    converter.__test_exact_union_variant_name("MissingArm").should be_nil
  end

  it "keeps the generated receiver bound for Array#reject(&.empty?)" do
    converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
      def keep_nonempty(values : Array(String)) : Array(String)
        values.reject(&.empty?)
      end

      keep_nonempty(["", "value"])
    CRYSTAL

    function = converter.module.functions.find { |candidate| candidate.name.starts_with?("keep_nonempty$") }
    function.should_not be_nil
    call_names = function.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
      instruction.as?(Adamas::HIR::Call).try(&.method_name)
    end

    call_names.should contain("String#empty?")
    call_names.should_not contain("empty?")
  end

  it "keeps the non-nil Array receiver for nilable try(&.[index]?)" do
    converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
      def lookup(values : Array(Int32)?, index : Int32) : Int32?
        values.try(&.[index]?)
      end

      lookup([7], 0)
    CRYSTAL

    function = converter.module.functions.find { |candidate| candidate.name.starts_with?("lookup$") }
    function.should_not be_nil
    call_names = function.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
      instruction.as?(Adamas::HIR::Call).try(&.method_name)
    end

    call_names.any? { |name| name.starts_with?("Array(Int32)#[]?") }.should be_true
    call_names.none? { |name| name.starts_with?("Nil#[]?") }.should be_true
  end

  it "carries a nil-initialized caller local across inlined yield iterations" do
    converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
      def walk_twice(&)
        index = 0
        while index < 2
          yield index
          index += 1
        end
      end

      def carried_slice(pattern : String) : String
        start_pos = nil

        walk_twice do |index|
          if index == 0
            start_pos = index
          else
            start = start_pos.not_nil! + 1
            return pattern.byte_slice(start, 1)
          end
        end

        pattern
      end

      carried_slice("ab")
    CRYSTAL

    function = converter.module.functions.find { |candidate| candidate.name.starts_with?("carried_slice$") }
    function.should_not be_nil
    call_names = function.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
      instruction.as?(Adamas::HIR::Call).try(&.method_name)
    end

    call_names.should contain("String#byte_slice$Int32_Int32")
    call_names.none? { |name| name.starts_with?("String#byte_slice$Nil") }.should be_true
  end

  it "distinguishes an early return before yield from a return after yield" do
    converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
      def pre_yield_return(flag : Bool, &)
        return if flag
        yield 1
      end

      def pre_yield_return_with_state(flag : Bool, &)
        return if flag
        yield 1
      end

      def pre_yield_return_with_nested_state(flag : Bool, &)
        return if flag
        yield 1
      end

      def pre_yield_return_with_condition_state(flag : Bool, &)
        return if flag
        yield 1
      end

      def pre_yield_return_with_local_state(flag : Bool, &)
        return if flag
        yield 1
      end

      def pre_yield_return_with_shadow(flag : Bool, &)
        return if flag
        yield 1
      end

      def pre_yield_return_with_nested_shadow(flag : Bool, &)
        return if flag
        yield 1
      end

      def post_yield_return(&)
        yield 1
        return
      end

      def postfix_yield_return(&)
        return true if yield 1
        false
      end

      def case_value_yield_return(&)
        case yield 1
        when 1
          return true
        end
        false
      end

      def case_condition_yield_return(&)
        case 1
        when yield 1
          return true
        end
        false
      end

      def return_order_driver : Nil
        total = 0
        pre_yield_return(false) { |value| value }
        pre_yield_return_with_state(false) { |value| total += value }
        pre_yield_return_with_nested_state(false) do |value|
          index = 0
          until index >= 1
            total += value
            index += 1
          end
        end
        pre_yield_return_with_condition_state(false) do |value|
          value if (total = value) > 0
        end
        pre_yield_return_with_local_state(false) do |value|
          local_only = value
          local_only
        end
        shadow = 0
        pre_yield_return_with_shadow(false) { |shadow| shadow = shadow + 1 }
        pre_yield_return_with_nested_shadow(false) do |value|
          [value].each { |shadow| shadow = shadow + 1 }
        end
        post_yield_return { |value| value }
        postfix_yield_return { |value| value }
        case_value_yield_return { |value| value }
        case_condition_yield_return { |value| value }
      end

      return_order_driver
    CRYSTAL

    function = converter.module.functions.find { |candidate| candidate.name == "return_order_driver" }
    function.should_not be_nil
    calls = function.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
      instruction.as?(Adamas::HIR::Call)
    end

    calls.none? { |call| call.method_name.starts_with?("pre_yield_return$") && call.has_block? }.should be_true
    calls.any? { |call| call.method_name.starts_with?("pre_yield_return_with_state$") && call.has_block? }.should be_true
    calls.any? { |call| call.method_name.starts_with?("pre_yield_return_with_nested_state$") && call.has_block? }.should be_true
    calls.any? { |call| call.method_name.starts_with?("pre_yield_return_with_condition_state$") && call.has_block? }.should be_true
    calls.none? { |call| call.method_name.starts_with?("pre_yield_return_with_local_state$") && call.has_block? }.should be_true
    calls.none? { |call| call.method_name.starts_with?("pre_yield_return_with_shadow$") && call.has_block? }.should be_true
    calls.none? { |call| call.method_name.starts_with?("pre_yield_return_with_nested_shadow$") && call.has_block? }.should be_true
    calls.any? { |call| call.method_name.starts_with?("post_yield_return") && call.has_block? }.should be_true
    calls.any? { |call| call.method_name.starts_with?("postfix_yield_return") && call.has_block? }.should be_true
    calls.any? { |call| call.method_name.starts_with?("case_value_yield_return") && call.has_block? }.should be_true
    calls.any? { |call| call.method_name.starts_with?("case_condition_yield_return") && call.has_block? }.should be_true
  end

  it "keeps nil out of shorthand and guarded-result receivers for a nilable Hash ivar" do
    converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
      class LookupOwner
        @values : Hash(String, String)?

        def initialize(@values : Hash(String, String)?)
        end

        def present?(name : String) : Bool
          if value = @values.try(&.[name]?)
            !value.empty?
          else
            false
          end
        end
      end

      LookupOwner.new({"key" => "value"}).present?("key")
    CRYSTAL

    function = converter.module.functions.find { |candidate| candidate.name.starts_with?("LookupOwner#present?") }
    function.should_not be_nil
    call_names = function.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
      instruction.as?(Adamas::HIR::Call).try(&.method_name)
    end

    call_names.any? { |name| name.starts_with?("Hash(String, String)#[]?") }.should be_true
    call_names.none? { |name| name.starts_with?("Nil#[]?") || name == "Nil#empty?" }.should be_true
  end
end

describe "assignment expression type preservation" do
  it "preserves a typed hash's named-tuple value shape in class-variable storage" do
    converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
      class TypedNamedTupleCache
        @@entries = {} of String => NamedTuple(name: String, count: Int32)

        def self.entries
          @@entries
        end
      end

      TypedNamedTupleCache.entries
    CRYSTAL

    reader = converter.module.functions.find { |function| function.name.starts_with?("TypedNamedTupleCache.entries") }
    reader.should_not be_nil
    class_var_get = reader.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
      instruction.as?(Adamas::HIR::ClassVarGet)
    end.find { |instruction| instruction.var_name == "entries" }
    class_var_get.should_not be_nil
    converter.__test_get_type_name_from_ref(class_var_get.not_nil!.type).should eq(
      "Hash(String, NamedTuple(name: String, count: Int32))"
    )
  end

  it "keeps a lazy-initialized class variable non-nil for the following index call" do
    converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
      class LazyRegistry
        @@values : Hash(String, String)? = nil

        def self.lookup(key : String) : String?
          values = @@values ||= Hash(String, String).new
          values[key]?
        end
      end

      LazyRegistry.lookup("key")
    CRYSTAL

    function = converter.module.functions.find { |candidate| candidate.name.starts_with?("LazyRegistry.lookup$") }
    function.should_not be_nil
    call_names = function.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
      instruction.as?(Adamas::HIR::Call).try(&.method_name)
    end

    call_names.any? { |name| name.starts_with?("Hash(String, String)#[]?") }.should be_true
    call_names.none? { |name| name.starts_with?("Nil#[]?") }.should be_true
  end

  it "keeps a lazy-initialized instance variable non-nil for the following index call" do
    converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
      class LazyIvarRegistry
        @values : Hash(String, String)?

        def initialize
          @values = nil
        end

        def lookup(key : String) : String?
          values = @values ||= Hash(String, String).new
          values[key]?
        end
      end

      LazyIvarRegistry.new.lookup("key")
    CRYSTAL

    function = converter.module.functions.find { |candidate| candidate.name.starts_with?("LazyIvarRegistry#lookup$") }
    function.should_not be_nil
    call_names = function.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
      instruction.as?(Adamas::HIR::Call).try(&.method_name)
    end

    call_names.any? { |name| name.starts_with?("Hash(String, String)#[]?") }.should be_true
    call_names.none? { |name| name.starts_with?("Nil#[]?") }.should be_true
  end
end

describe "yield classification cache" do
  it "treats false and true as authoritative cached values" do
    converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
      class YieldCacheValueProbe
        def plain : Int32
          1
        end

        def yielding(&) : Int32
          yield
          1
        end
      end

      probe = YieldCacheValueProbe.new
      probe.plain
      probe.yielding { nil }
    CRYSTAL

    plain_name = converter.__test_function_def_names("YieldCacheValueProbe#plain").first
    yielding_name = converter.__test_function_def_names("YieldCacheValueProbe#yielding").first

    converter.__test_seeded_yield_cache_result(yielding_name, false).should be_false
    converter.__test_seeded_yield_cache_result(plain_name, true).should be_true
  end

  it "recognizes standalone yield tokens without mixing character and byte offsets" do
    converter = lower_program_with_main("1", source_backed: true)

    converter.__test_macro_text_contains_yield("yield").should be_true
    converter.__test_macro_text_contains_yield("before; yield(value)").should be_true
    converter.__test_macro_text_contains_yield("λ yield").should be_true
    converter.__test_macro_text_contains_yield("").should be_false
    converter.__test_macro_text_contains_yield("yiel").should be_false
    converter.__test_macro_text_contains_yield("yield_value preyield yield2").should be_false
  end
end

describe "yield parameter flow narrowing" do
  it "keeps a guard-narrowed yielded value non-nil in the caller block" do
    converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
      class YieldToken
        def []?(index : Int32) : String?
          nil
        end
      end

      class GuardedProducer
        def self.find : YieldToken?
          YieldToken.new
        end

        def self.with_token(&)
          token = find
          return unless token
          while token
            yield token
            token = find
          end
        end
      end

      def consume_token(token)
        token[0]?
      end

      GuardedProducer.with_token { |token| consume_token(token) }
    CRYSTAL

    consume_functions = converter.module.functions.select do |candidate|
      candidate.name.starts_with?("consume_token$")
    end
    consume_functions.empty?.should be_false
    consume_functions.none? { |candidate| candidate.name.includes?("Nil |") }.should be_true
    call_names = consume_functions.flat_map(&.blocks).flat_map(&.instructions).compact_map do |instruction|
      instruction.as?(Adamas::HIR::Call).try(&.method_name)
    end

    call_names.any? { |name| name.starts_with?("YieldToken#[]?") }.should be_true
    call_names.none? { |name| name.starts_with?("Nil#[]?") }.should be_true
  end
end

describe "while assignment flow narrowing" do
  it "keeps an assigned nilable Proc non-nil inside the loop body" do
    converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
      class ExitHandlerException
      end

      module ExitHandlerStore
        def self.add(handler)
          handlers = @@handlers ||= [] of Int32, ExitHandlerException? ->
          handlers << handler
        end

        def self.synchronize(&)
          yield
        end

        def self.run(status : Int32) : Int32
          return status unless @@handlers
          while handler = synchronize { @@handlers.try(&.pop?) }
            begin
              handler.call status, nil
            rescue handler_exception
              status = 1
            end
          end
          status
        end
      end

      ExitHandlerStore.add(->(status : Int32, exception : ExitHandlerException?) { nil })
      ExitHandlerStore.run(0)
    CRYSTAL

    function = converter.module.functions.find { |candidate| candidate.name.starts_with?("ExitHandlerStore.run$") }
    function.should_not be_nil
    call_names = function.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
      instruction.as?(Adamas::HIR::Call).try(&.method_name)
    end

    call_names.any? { |name| name.starts_with?("Proc") && name.includes?("#call") }.should be_true
    call_names.none? { |name| name.starts_with?("Nil#call") }.should be_true
  end
end

describe "loop assignment discovery through begin scopes" do
  it "keeps protected-body and ensure assignments loop-carried" do
    arena, roots = parse(<<-CRYSTAL)
      def probe(values : Array(UInt32)) : UInt32?
        result : UInt32? = nil
        index = 0
        while index < values.size
          begin
            result = values[index]
          ensure
            index = index
          end
          index += 1
        end
        result
      end
    CRYSTAL
    def_node = roots.compact_map { |id| arena[id].as?(Adamas::Compiler::Frontend::DefNode) }.first
    while_node = def_node.body.not_nil!.compact_map do |id|
      arena[id].as?(Adamas::Compiler::Frontend::WhileNode)
    end.first
    converter = Adamas::HIR::AstToHir.new(arena)

    assigned = converter.__test_collect_assigned_vars(while_node.body)
    assigned.should contain("result")
    assigned.should contain("index")
  end
end

describe "signature short-name resolution" do
  it "does not preinsert a missing short-name key" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_resolve_signature_short_name_without_entry("Missing").should be_nil
    converter.__test_short_type_index_has_key("Missing").should be_false
  end

  it "fails closed when a short-name candidate set is empty" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_resolve_signature_short_name("Missing", Set(String).new).should be_nil
  end

  it "keeps singleton and shortest-candidate selection" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_resolve_signature_short_name("Only", Set{"Outer::Only"}).should eq("Outer::Only")
    converter.__test_resolve_signature_short_name(
      "Many",
      Set{"Outer::VeryLongMany", "Other::Many"}
    ).should eq("Other::Many")
  end
end

# Helper to parse Crystal code and get AST
private def parse(code : String) : {Adamas::Compiler::Frontend::ArenaLike, Array(Adamas::Compiler::Frontend::ExprId)}
  lexer = Adamas::Compiler::Frontend::Lexer.new(code)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  {result.arena, result.roots}
end

# Helper to parse and lower a function
private def lower_function(code : String) : Adamas::HIR::Function
  arena, exprs = parse(code)
  converter = Adamas::HIR::AstToHir.new(arena)

  # Find DefNode
  def_expr = exprs.find do |expr_id|
    arena[expr_id].is_a?(Adamas::Compiler::Frontend::DefNode)
  end

  raise "No function definition found" unless def_expr
  def_node = arena[def_expr].as(Adamas::Compiler::Frontend::DefNode)

  converter.lower_def(def_node)
end

private def lower_function_with_converter(code : String) : {Adamas::HIR::Function, Adamas::HIR::AstToHir}
  arena, exprs = parse(code)
  converter = Adamas::HIR::AstToHir.new(arena)

  def_expr = exprs.find do |expr_id|
    arena[expr_id].is_a?(Adamas::Compiler::Frontend::DefNode)
  end

  raise "No function definition found" unless def_expr
  def_node = arena[def_expr].as(Adamas::Compiler::Frontend::DefNode)

  {converter.lower_def(def_node), converter}
end

private def lower_program(code : String) : Adamas::HIR::AstToHir
  arena, exprs = parse(code)
  converter = Adamas::HIR::AstToHir.new(arena)
  converter.arena = arena

  enum_nodes = [] of Adamas::Compiler::Frontend::EnumNode
  module_nodes = [] of Adamas::Compiler::Frontend::ModuleNode
  class_nodes = [] of Adamas::Compiler::Frontend::ClassNode
  def_nodes = [] of Adamas::Compiler::Frontend::DefNode

  exprs.each do |expr_id|
    node = arena[expr_id]
    case node
    when Adamas::Compiler::Frontend::EnumNode
      enum_nodes << node
    when Adamas::Compiler::Frontend::ModuleNode
      module_nodes << node
    when Adamas::Compiler::Frontend::ClassNode
      class_nodes << node
    when Adamas::Compiler::Frontend::DefNode
      def_nodes << node
    end
  end

  enum_nodes.each { |node| converter.register_enum(node) }
  module_nodes.each { |node| converter.register_module(node) }
  class_nodes.each { |node| converter.register_class(node) }
  def_nodes.each { |node| converter.register_function(node) }

  module_nodes.each { |node| converter.lower_module(node) }
  class_nodes.each { |node| converter.lower_class(node) }
  def_nodes.each { |node| converter.lower_def(node) }

  converter
end

private def lower_program_with_main(
  code : String,
  source_backed : Bool = false,
  source_path : String? = nil,
  stdlib_root : String? = nil,
  semantic_call_targets : Bool = false,
  profile_call_resolution : Bool = false,
) : Adamas::HIR::AstToHir
  arena, exprs = parse(code)
  sources_by_arena = if source_backed || source_path
                       {arena.object_id.to_u64 => code}
                     end
  paths_by_arena = if path = source_path
                     {arena.object_id.to_u64 => path}
                   end
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: sources_by_arena,
    paths_by_arena: paths_by_arena,
    stdlib_root: stdlib_root,
  )
  converter.arena = arena

  if semantic_call_targets
    program = Adamas::Compiler::Frontend::Program.new(arena, exprs)
    analyzer = Adamas::Compiler::Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    name_result = analyzer.resolve_names
    engine = analyzer.infer_types(name_result.identifier_symbols)
    unless analyzer.semantic_diagnostics.empty? &&
           analyzer.name_resolver_diagnostics.empty? &&
           engine.diagnostics.empty?
      raise "semantic call-target fixture failed analysis"
    end
    converter.bind_semantic_call_targets(arena, engine.context)
  end

  enum_nodes = [] of Adamas::Compiler::Frontend::EnumNode
  module_nodes = [] of Adamas::Compiler::Frontend::ModuleNode
  class_nodes = [] of Adamas::Compiler::Frontend::ClassNode
  def_nodes = [] of Adamas::Compiler::Frontend::DefNode
  alias_nodes = [] of Adamas::Compiler::Frontend::AliasNode
  main_exprs = [] of UInt64

  exprs.each do |expr_id|
    node = arena[expr_id]
    case node
    when Adamas::Compiler::Frontend::EnumNode
      enum_nodes << node
    when Adamas::Compiler::Frontend::ModuleNode
      module_nodes << node
    when Adamas::Compiler::Frontend::ClassNode
      class_nodes << node
    when Adamas::Compiler::Frontend::DefNode
      def_nodes << node
    when Adamas::Compiler::Frontend::AliasNode
      alias_nodes << node
    when Adamas::Compiler::Frontend::CallNode
      main_exprs << expr_id.index.to_u64
    end
  end

  enum_nodes.each { |node| converter.register_enum(node) }
  module_nodes.each { |node| converter.register_module(node) }
  class_nodes.each { |node| converter.register_class(node) }
  alias_nodes.each { |node| converter.register_alias(node) }
  def_nodes.each { |node| converter.register_function(node) }

  module_nodes.each { |node| converter.lower_module(node) }
  class_nodes.each { |node| converter.lower_class(node) }
  def_nodes.each { |node| converter.lower_def(node) }

  converter.__test_begin_call_resolution_profile if profile_call_resolution
  converter.lower_main(main_exprs) if main_exprs.size > 0

  converter
end

# Reproduce the self-host source-fallback path without changing production AST
# APIs: clear the parsed initialize parameter storage while retaining the
# source spans used by `source_ivar_param_entries`.
private def clear_initialize_parameter_storage(
  arena : Adamas::Compiler::Frontend::ArenaLike,
  exprs : Array(Adamas::Compiler::Frontend::ExprId),
) : Nil
  exprs.each do |expr_id|
    node = arena[expr_id]
    case node
    when Adamas::Compiler::Frontend::ModuleNode
      clear_initialize_parameter_storage(arena, node.body.not_nil!) if node.body
    when Adamas::Compiler::Frontend::ClassNode
      clear_initialize_parameter_storage(arena, node.body.not_nil!) if node.body
    when Adamas::Compiler::Frontend::BlockNode
      clear_initialize_parameter_storage(arena, node.body)
    when Adamas::Compiler::Frontend::DefNode
      if (safe_name = node.name) && String.new(safe_name) == "initialize"
        params = node.params
        if params
          params.clear
        end
      end
      clear_initialize_parameter_storage(arena, node.body.not_nil!) if node.body
    end
  end
end

# Reproduce the narrower self-host loss mode: keep parameter names, defaults,
# separators, and visibility wrappers, but drop a generic type annotation and
# its span. Source text remains available to the converter as the recovery
# witness, matching an erased generic `Hash(T, Nil)` annotation in stage2.
private def clear_generic_initialize_type_annotations(
  arena : Adamas::Compiler::Frontend::ArenaLike,
  exprs : Array(Adamas::Compiler::Frontend::ExprId),
) : Nil
  exprs.each do |expr_id|
    node = arena[expr_id]
    case node
    when Adamas::Compiler::Frontend::ModuleNode
      clear_generic_initialize_type_annotations(arena, node.body.not_nil!) if node.body
    when Adamas::Compiler::Frontend::ClassNode
      clear_generic_initialize_type_annotations(arena, node.body.not_nil!) if node.body
    when Adamas::Compiler::Frontend::BlockNode
      clear_generic_initialize_type_annotations(arena, node.body)
    when Adamas::Compiler::Frontend::DefNode
      if (safe_name = node.name) && String.new(safe_name) == "initialize"
        params = node.params
        if params
          replacement = [] of Adamas::Compiler::Frontend::Parameter
          params.each do |param|
            type_annotation = param.type_annotation
            if type_annotation && String.new(type_annotation).includes?("T")
              replacement << Adamas::Compiler::Frontend::Parameter.new(
                param.name,
                param.external_name,
                nil,
                param.default_value,
                param.span,
                param.name_span,
                param.external_name_span,
                nil,
                param.default_span,
                param.is_splat,
                param.is_double_splat,
                param.is_block,
                param.is_instance_var,
              )
            else
              replacement << param
            end
          end
          params.clear
          params.concat(replacement)
        end
      end
      clear_generic_initialize_type_annotations(arena, node.body.not_nil!) if node.body
    end
  end
end

# Reproduce the non-empty self-host corruption observed on protected implicit
# ivar parameters: retain every parser-owned shape bit (name, external name,
# named-only separator, defaults, spans, and body), but replace the raw type
# token with a plausible neighboring annotation.  The source text remains
# available as the authoritative witness.
private def corrupt_nonempty_initialize_ivar_annotation(
  arena : Adamas::Compiler::Frontend::ArenaLike,
  exprs : Array(Adamas::Compiler::Frontend::ExprId),
) : Nil
  exprs.each do |expr_id|
    node = arena[expr_id]
    case node
    when Adamas::Compiler::Frontend::ModuleNode
      corrupt_nonempty_initialize_ivar_annotation(arena, node.body.not_nil!) if node.body
    when Adamas::Compiler::Frontend::ClassNode
      corrupt_nonempty_initialize_ivar_annotation(arena, node.body.not_nil!) if node.body
    when Adamas::Compiler::Frontend::BlockNode
      corrupt_nonempty_initialize_ivar_annotation(arena, node.body)
    when Adamas::Compiler::Frontend::DefNode
      if (safe_name = node.name) && String.new(safe_name) == "initialize"
        params = node.params
        if params
          replacement = [] of Adamas::Compiler::Frontend::Parameter
          params.each do |param|
            type_annotation = param.type_annotation
            type_text = type_annotation ? String.new(type_annotation) : ""
            if param.is_instance_var && type_text.includes?("Hash(")
              replacement_param = Adamas::Compiler::Frontend::Parameter.new(
                param.name,
                param.external_name,
                CORRUPTED_PARAMETER_TYPE_SOURCE.to_slice,
                param.default_value,
                param.span,
                param.name_span,
                param.external_name_span,
                # The self-host corruption can drop the dedicated type span
                # while retaining the full parameter span and all shape bits.
                nil,
                param.default_span,
                param.is_splat,
                param.is_double_splat,
                param.is_block,
                param.is_instance_var,
              )
              replacement << replacement_param
            else
              replacement << param
            end
          end
          params.clear
          params.concat(replacement)
        end
      end
      corrupt_nonempty_initialize_ivar_annotation(arena, node.body.not_nil!) if node.body
    end
  end
end

# Reproduce the narrower self-host loss mode where an implicit-ivar parameter
# keeps its non-zero full span, source, external name, default, and body,
# while its raw type token is replaced with a plausible non-empty placeholder,
# but loses the parser's ivar identity bit and raw `@` spelling.  The separate
# named-only `*` separator intentionally survives, matching the production
# shape whose source witness must be enough to trigger recovery.
private def lose_nonempty_initialize_ivar_identity(
  arena : Adamas::Compiler::Frontend::ArenaLike,
  exprs : Array(Adamas::Compiler::Frontend::ExprId),
) : Nil
  exprs.each do |expr_id|
    node = arena[expr_id]
    case node
    when Adamas::Compiler::Frontend::ModuleNode
      lose_nonempty_initialize_ivar_identity(arena, node.body.not_nil!) if node.body
    when Adamas::Compiler::Frontend::ClassNode
      lose_nonempty_initialize_ivar_identity(arena, node.body.not_nil!) if node.body
    when Adamas::Compiler::Frontend::BlockNode
      lose_nonempty_initialize_ivar_identity(arena, node.body)
    when Adamas::Compiler::Frontend::DefNode
      if (safe_name = node.name) && String.new(safe_name) == "initialize"
        params = node.params
        if params
          replacement = [] of Adamas::Compiler::Frontend::Parameter
          params.each do |param|
            type_annotation = param.type_annotation
            type_text = type_annotation ? String.new(type_annotation) : ""
            if param.is_instance_var && type_text.includes?("Hash(")
              replacement << Adamas::Compiler::Frontend::Parameter.new(
                # Keep the parser-owned spans and source witness, but make the
                # raw name look like an ordinary internal parameter and retain
                # a plausible non-empty corrupted type token.
                "hash".to_slice,
                param.external_name,
                CORRUPTED_PARAMETER_TYPE_SOURCE.to_slice,
                param.default_value,
                param.span,
                # Drop the dedicated name span as well; with the raw name
                # normalized above this leaves DefParamInfo unable to recover
                # the `@ivar` identity from source-backed parameter metadata.
                nil,
                param.external_name_span,
                nil,
                param.default_span,
                param.is_splat,
                param.is_double_splat,
                param.is_block,
                false,
              )
            else
              replacement << param
            end
          end
          params.clear
          params.concat(replacement)
        end
      end
      lose_nonempty_initialize_ivar_identity(arena, node.body.not_nil!) if node.body
    end
  end
end

private def lower_source_backed_program_with_corrupted_nonempty_annotation(code : String) : Adamas::HIR::AstToHir
  arena, exprs = parse(code)
  corrupt_nonempty_initialize_ivar_annotation(arena, exprs)
  converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => code})
  converter.arena = arena

  enum_nodes = [] of Adamas::Compiler::Frontend::EnumNode
  module_nodes = [] of Adamas::Compiler::Frontend::ModuleNode
  class_nodes = [] of Adamas::Compiler::Frontend::ClassNode
  def_nodes = [] of Adamas::Compiler::Frontend::DefNode
  alias_nodes = [] of Adamas::Compiler::Frontend::AliasNode
  main_exprs = [] of UInt64

  exprs.each do |expr_id|
    node = arena[expr_id]
    case node
    when Adamas::Compiler::Frontend::EnumNode
      enum_nodes << node
    when Adamas::Compiler::Frontend::ModuleNode
      module_nodes << node
    when Adamas::Compiler::Frontend::ClassNode
      class_nodes << node
    when Adamas::Compiler::Frontend::DefNode
      def_nodes << node
    when Adamas::Compiler::Frontend::AliasNode
      alias_nodes << node
    when Adamas::Compiler::Frontend::CallNode
      main_exprs << expr_id.index.to_u64
    end
  end

  enum_nodes.each { |node| converter.register_enum(node) }
  module_nodes.each { |node| converter.register_module(node) }
  class_nodes.each { |node| converter.register_class(node) }
  alias_nodes.each { |node| converter.register_alias(node) }
  def_nodes.each { |node| converter.register_function(node) }

  module_nodes.each { |node| converter.lower_module(node) }
  class_nodes.each { |node| converter.lower_class(node) }
  def_nodes.each { |node| converter.lower_def(node) }
  converter.lower_main(main_exprs) if main_exprs.size > 0

  converter
end

private def lower_source_backed_program_with_lost_nonempty_ivar_identity(code : String) : Adamas::HIR::AstToHir
  arena, exprs = parse(code)
  lose_nonempty_initialize_ivar_identity(arena, exprs)
  converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => code})
  converter.arena = arena

  enum_nodes = [] of Adamas::Compiler::Frontend::EnumNode
  module_nodes = [] of Adamas::Compiler::Frontend::ModuleNode
  class_nodes = [] of Adamas::Compiler::Frontend::ClassNode
  def_nodes = [] of Adamas::Compiler::Frontend::DefNode
  alias_nodes = [] of Adamas::Compiler::Frontend::AliasNode
  main_exprs = [] of UInt64

  exprs.each do |expr_id|
    node = arena[expr_id]
    case node
    when Adamas::Compiler::Frontend::EnumNode
      enum_nodes << node
    when Adamas::Compiler::Frontend::ModuleNode
      module_nodes << node
    when Adamas::Compiler::Frontend::ClassNode
      class_nodes << node
    when Adamas::Compiler::Frontend::DefNode
      def_nodes << node
    when Adamas::Compiler::Frontend::AliasNode
      alias_nodes << node
    when Adamas::Compiler::Frontend::CallNode
      main_exprs << expr_id.index.to_u64
    end
  end

  enum_nodes.each { |node| converter.register_enum(node) }
  module_nodes.each { |node| converter.register_module(node) }
  class_nodes.each { |node| converter.register_class(node) }
  alias_nodes.each { |node| converter.register_alias(node) }
  def_nodes.each { |node| converter.register_function(node) }

  module_nodes.each { |node| converter.lower_module(node) }
  class_nodes.each { |node| converter.lower_class(node) }
  def_nodes.each { |node| converter.lower_def(node) }
  converter.lower_main(main_exprs) if main_exprs.size > 0

  converter
end

private def lower_source_backed_program_with_lost_nonempty_typed_parameters(code : String) : Adamas::HIR::AstToHir
  arena, exprs = parse(code)
  lose_nonempty_typed_parameter_metadata(arena, exprs)
  converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => code})
  converter.arena = arena

  enum_nodes = [] of Adamas::Compiler::Frontend::EnumNode
  module_nodes = [] of Adamas::Compiler::Frontend::ModuleNode
  class_nodes = [] of Adamas::Compiler::Frontend::ClassNode
  def_nodes = [] of Adamas::Compiler::Frontend::DefNode
  alias_nodes = [] of Adamas::Compiler::Frontend::AliasNode

  exprs.each do |expr_id|
    node = arena[expr_id]
    case node
    when Adamas::Compiler::Frontend::EnumNode
      enum_nodes << node
    when Adamas::Compiler::Frontend::ModuleNode
      module_nodes << node
    when Adamas::Compiler::Frontend::ClassNode
      class_nodes << node
    when Adamas::Compiler::Frontend::DefNode
      def_nodes << node
    when Adamas::Compiler::Frontend::AliasNode
      alias_nodes << node
    end
  end

  enum_nodes.each { |node| converter.register_enum(node) }
  module_nodes.each { |node| converter.register_module(node) }
  class_nodes.each { |node| converter.register_class(node) }
  alias_nodes.each { |node| converter.register_alias(node) }
  def_nodes.each { |node| converter.register_function(node) }

  module_nodes.each { |node| converter.lower_module(node) }
  class_nodes.each { |node| converter.lower_class(node) }
  def_nodes.each { |node| converter.lower_def(node) }
  converter
end

private def find_initialize_def(
  arena : Adamas::Compiler::Frontend::ArenaLike,
  exprs : Array(Adamas::Compiler::Frontend::ExprId),
) : Adamas::Compiler::Frontend::DefNode?
  exprs.each do |expr_id|
    node = arena[expr_id]
    case node
    when Adamas::Compiler::Frontend::ClassNode
      if body = node.body
        if found = find_initialize_def(arena, body.not_nil!)
          return found
        end
      end
    when Adamas::Compiler::Frontend::ModuleNode
      if body = node.body
        if found = find_initialize_def(arena, body.not_nil!)
          return found
        end
      end
    when Adamas::Compiler::Frontend::BlockNode
      if found = find_initialize_def(arena, node.body)
        return found
      end
    when Adamas::Compiler::Frontend::DefNode
      if (safe_name = node.name) && String.new(safe_name) == "initialize"
        return node
      end
    end
  end
  nil
end

private def lower_source_backed_program_with_erased_generic_annotations(code : String) : Adamas::HIR::AstToHir
  arena, exprs = parse(code)
  clear_generic_initialize_type_annotations(arena, exprs)
  converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => code})
  converter.arena = arena

  enum_nodes = [] of Adamas::Compiler::Frontend::EnumNode
  module_nodes = [] of Adamas::Compiler::Frontend::ModuleNode
  class_nodes = [] of Adamas::Compiler::Frontend::ClassNode
  def_nodes = [] of Adamas::Compiler::Frontend::DefNode
  alias_nodes = [] of Adamas::Compiler::Frontend::AliasNode
  main_exprs = [] of UInt64

  exprs.each do |expr_id|
    node = arena[expr_id]
    case node
    when Adamas::Compiler::Frontend::EnumNode
      enum_nodes << node
    when Adamas::Compiler::Frontend::ModuleNode
      module_nodes << node
    when Adamas::Compiler::Frontend::ClassNode
      class_nodes << node
    when Adamas::Compiler::Frontend::DefNode
      def_nodes << node
    when Adamas::Compiler::Frontend::AliasNode
      alias_nodes << node
    when Adamas::Compiler::Frontend::CallNode
      main_exprs << expr_id.index.to_u64
    end
  end

  enum_nodes.each { |node| converter.register_enum(node) }
  module_nodes.each { |node| converter.register_module(node) }
  class_nodes.each { |node| converter.register_class(node) }
  alias_nodes.each { |node| converter.register_alias(node) }
  def_nodes.each { |node| converter.register_function(node) }

  module_nodes.each { |node| converter.lower_module(node) }
  class_nodes.each { |node| converter.lower_class(node) }
  def_nodes.each { |node| converter.lower_def(node) }
  converter.lower_main(main_exprs) if main_exprs.size > 0

  converter
end

private def lower_source_backed_program_with_empty_initialize_params(code : String) : Adamas::HIR::AstToHir
  arena, exprs = parse(code)
  clear_initialize_parameter_storage(arena, exprs)
  converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => code})
  converter.arena = arena

  enum_nodes = [] of Adamas::Compiler::Frontend::EnumNode
  module_nodes = [] of Adamas::Compiler::Frontend::ModuleNode
  class_nodes = [] of Adamas::Compiler::Frontend::ClassNode
  def_nodes = [] of Adamas::Compiler::Frontend::DefNode
  alias_nodes = [] of Adamas::Compiler::Frontend::AliasNode
  main_exprs = [] of UInt64

  exprs.each do |expr_id|
    node = arena[expr_id]
    case node
    when Adamas::Compiler::Frontend::EnumNode
      enum_nodes << node
    when Adamas::Compiler::Frontend::ModuleNode
      module_nodes << node
    when Adamas::Compiler::Frontend::ClassNode
      class_nodes << node
    when Adamas::Compiler::Frontend::DefNode
      def_nodes << node
    when Adamas::Compiler::Frontend::AliasNode
      alias_nodes << node
    when Adamas::Compiler::Frontend::CallNode
      main_exprs << expr_id.index.to_u64
    end
  end

  enum_nodes.each { |node| converter.register_enum(node) }
  module_nodes.each { |node| converter.register_module(node) }
  class_nodes.each { |node| converter.register_class(node) }
  alias_nodes.each { |node| converter.register_alias(node) }
  def_nodes.each { |node| converter.register_function(node) }

  module_nodes.each { |node| converter.lower_module(node) }
  class_nodes.each { |node| converter.lower_class(node) }
  def_nodes.each { |node| converter.lower_def(node) }
  converter.lower_main(main_exprs) if main_exprs.size > 0

  converter
end

private def lower_program_with_sources(
  code : String,
  source_path : String? = nil,
  stdlib_root : String? = nil,
) : Adamas::HIR::AstToHir
  arena, exprs = parse(code)
  sources_by_arena = {arena.object_id.to_u64 => code}
  paths_by_arena = if path = source_path
                     {arena.object_id.to_u64 => path}
                   end
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: sources_by_arena,
    paths_by_arena: paths_by_arena,
    stdlib_root: stdlib_root,
  )
  converter.arena = arena

  module_nodes = [] of Adamas::Compiler::Frontend::ModuleNode
  class_nodes = [] of Adamas::Compiler::Frontend::ClassNode
  def_nodes = [] of Adamas::Compiler::Frontend::DefNode
  macro_nodes = [] of Adamas::Compiler::Frontend::MacroDefNode
  main_exprs = [] of UInt64

  exprs.each do |expr_id|
    node = arena[expr_id]
    case node
    when Adamas::Compiler::Frontend::ModuleNode
      module_nodes << node
    when Adamas::Compiler::Frontend::ClassNode
      class_nodes << node
    when Adamas::Compiler::Frontend::DefNode
      def_nodes << node
    when Adamas::Compiler::Frontend::MacroDefNode
      macro_nodes << node
    when Adamas::Compiler::Frontend::CallNode
      main_exprs << expr_id.index.to_u64
    end
  end

  module_nodes.each { |node| converter.register_module(node) }
  macro_nodes.each { |node| converter.register_macro(node) }
  class_nodes.each { |node| converter.register_class(node) }
  def_nodes.each { |node| converter.register_function(node) }

  module_nodes.each { |node| converter.lower_module(node) }
  class_nodes.each { |node| converter.lower_class(node) }
  def_nodes.each { |node| converter.lower_def(node) }
  converter.lower_main(main_exprs) if main_exprs.size > 0

  converter
end

# Helper to get HIR text output
private def hir_text(func : Adamas::HIR::Function) : String
  String.build { |io| func.to_s(io) }
end

describe Adamas::HIR::AstToHir do
  describe "lowering demand ledger" do
    it "records raw demand across queue sources without collapsing shape" do
      previous_filter = ENV["ADAMAS_HIR_DEMAND_LEDGER"]?
      previous_limit = ENV["ADAMAS_HIR_DEMAND_LEDGER_LIMIT"]?
      ENV["ADAMAS_HIR_DEMAND_LEDGER"] = "LedgerOwner#probe"
      ENV["ADAMAS_HIR_DEMAND_LEDGER_LIMIT"] = "4"

      begin
        converter = lower_program(<<-CRYSTAL)
          class LedgerOwner
            def probe(value : Int32)
              value
            end
          end
          CRYSTAL
        demand_name = converter.__test_function_def_names("LedgerOwner#probe").first

        converter.__test_record_lowering_demand(
          demand_name,
          "missing_scan",
          [Adamas::HIR::TypeRef::INT32],
        )
        converter.__test_record_lowering_demand(
          demand_name,
          "layout_invalidate",
          [Adamas::HIR::TypeRef::INT32],
        )
        converter.__test_record_lowering_demand(
          demand_name,
          "missing_scan",
          [Adamas::HIR::TypeRef::INT32],
          [true],
          ["LedgerKind"] of String?,
        )
        converter.__test_record_lowering_demand(
          demand_name,
          "missing_scan",
          [Adamas::HIR::TypeRef::INT32],
          [true],
          ["OtherKind"] of String?,
        )
        converter.__test_record_lowering_demand(
          demand_name,
          "rta_undefer",
          [Adamas::HIR::TypeRef::INT32],
        )

        events = converter.__test_lowering_demand_ledger_events
        events.size.should eq(4)
        converter.__test_lowering_demand_ledger_full?.should be_true
        events.first.should contain("source=missing_scan")
        events.first.should contain("def_node=")
        events.first.should contain("def_arena=")
        events.first.should contain("selected_def_source=exact")
        events.first.should contain("arg_types=4")
        events[1].should contain("source=layout_invalidate")
        events[1].should contain("body=")
        events[1].should contain("def_rev=")
        events[1].should contain("state_rev=")
        events[1].should contain("queue_rev=")
        events[2].should contain("literals=1")
        events[2].should contain("enum_names=LedgerKind")
        events[3].should contain("enum_names=OtherKind")
      ensure
        if previous_filter
          ENV["ADAMAS_HIR_DEMAND_LEDGER"] = previous_filter
        else
          ENV.delete("ADAMAS_HIR_DEMAND_LEDGER")
        end
        if previous_limit
          ENV["ADAMAS_HIR_DEMAND_LEDGER_LIMIT"] = previous_limit
        else
          ENV.delete("ADAMAS_HIR_DEMAND_LEDGER_LIMIT")
        end
      end
    end

    it "does no ledger work when the filter is absent" do
      previous_filter = ENV["ADAMAS_HIR_DEMAND_LEDGER"]?
      ENV.delete("ADAMAS_HIR_DEMAND_LEDGER")

      begin
        converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
        converter.__test_record_lowering_demand(
          "LedgerOwner#probe$Int32",
          "missing_scan",
          [Adamas::HIR::TypeRef::INT32],
        )
        converter.__test_lowering_demand_ledger_events.should be_empty
      ensure
        ENV["ADAMAS_HIR_DEMAND_LEDGER"] = previous_filter if previous_filter
      end
    end
  end

  describe "method-index separator contract" do
    it "prefers exact separators and keeps only class-to-instance fallback" do
      converter = lower_program_with_main("1")
      instance_only = ["Owner#probe$arity0"]
      class_only = ["Owner.probe$arity0"]
      mixed = [instance_only.first, class_only.first]

      converter.__test_method_index_call_candidates_for_separator(instance_only, '#')
        .should eq(instance_only)
      converter.__test_method_index_call_candidates_for_separator(class_only, '.')
        .should eq(class_only)

      converter.__test_method_index_call_candidates_for_separator(mixed, '#')
        .should eq(instance_only)
      converter.__test_method_index_call_candidates_for_separator(mixed, '.')
        .should eq(class_only)

      # `extend self` can expose an instance registration to a class-form call.
      converter.__test_method_index_call_candidates_for_separator(instance_only, '.')
        .should eq(instance_only)
      # The reverse would let Child.foo mask Parent#foo for a Child#foo call.
      converter.__test_method_index_call_candidates_for_separator(class_only, '#')
        .should be_empty
    end
  end

  describe "method-index incremental maintenance" do
    it "indexes each late definition once without rescanning the old prefix" do
      converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
        class MethodIndexProbe
          def pick(value : Int32) : Int32
            value
          end

          def pick(value : String) : String
            value
          end

          def self.pick(value : Bool) : Bool
            value
          end
        end

        1
        CRYSTAL

      source_name = converter.__test_function_def_names("MethodIndexProbe#pick$Int32").first
      initial_candidates = converter.__test_method_index_candidates("MethodIndexProbe", "pick")
      initial_candidates.should contain(source_name)
      initial_candidates.should_not contain("MethodIndexProbe.pick$Bool")
      converter.__test_method_index_candidates("MethodIndexProbe", "pick", '.').should eq([
        "MethodIndexProbe.pick$Bool",
      ])
      initial_state = converter.__test_method_index_state
      initial_state[:built].should be_true
      initial_state[:processed].should eq(initial_state[:defs_size])
      initial_state[:size_at_build].should eq(initial_state[:defs_size])

      converter.__test_reregister_function_def(source_name)
      converter.__test_method_index_state.should eq(initial_state)

      alias_name = "MethodIndexProbe(String)#pick$Late"
      class_alias_name = "MethodIndexProbe(String).pick$Late"
      converter.__test_add_function_def_alias(source_name, alias_name)
      converter.__test_add_function_def_alias("MethodIndexProbe.pick$Bool", class_alias_name)
      late_state = converter.__test_method_index_state
      late_state[:built].should be_true
      late_state[:processed].should eq(late_state[:defs_size])
      late_state[:size_at_build].should eq(late_state[:defs_size])

      late_candidates = converter.__test_method_index_candidates("MethodIndexProbe(String)", "pick")
      late_candidates.count(alias_name).should eq(1)
      late_class_candidates = converter.__test_method_index_candidates("MethodIndexProbe(String)", "pick", '.')
      late_class_candidates.count(class_alias_name).should eq(1)
      converter.__test_method_index_all_candidates("MethodIndexProbe", "pick").should eq([
        "MethodIndexProbe#pick$Int32",
        "MethodIndexProbe#pick$String",
        "MethodIndexProbe.pick$Bool",
        alias_name,
        class_alias_name,
      ])
    end
  end

  describe "exact call-resolution memo" do
    it "reuses the exact selected overload and DefNode" do
      converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
        class CallMemoBox
          def choose(value : Int32) : Int32
            10
          end

          def choose(value : String) : Int32
            20
          end
        end

        CallMemoBox.new.choose(1)
        CRYSTAL
      converter.__test_reset_call_resolution_memo
      int32 = converter.__test_type_ref_for_name("Int32")

      first = converter.__test_resolve_call_memo("CallMemoBox#choose", [int32])
      second = converter.__test_resolve_call_memo("CallMemoBox#choose", [int32])

      first[0].should eq("CallMemoBox#choose$Int32")
      first[1].should_not be_nil
      second.should eq(first)
      converter.__test_call_resolution_memo_stats.should eq({
        entries:     1,
        hits:        1_i64,
        misses:      1_i64,
        store_skips: 0_i64,
      })

      converter.__test_perturb_unrelated_lowering_work("__call_resolution_memo_noise")
      converter.__test_resolve_call_memo("CallMemoBox#choose", [int32]).should eq(first)
      converter.__test_call_resolution_memo_stats[:hits].should eq(2)
      converter.__test_call_resolution_memo_stats[:misses].should eq(1)

      converter.__test_perturb_unrelated_hir_work("__call_resolution_memo_hir_noise")
      converter.__test_resolve_call_memo("CallMemoBox#choose", [int32]).should eq(first)
      converter.__test_call_resolution_memo_stats[:hits].should eq(3)
      converter.__test_call_resolution_memo_stats[:misses].should eq(1)

      converter.__test_reregister_function_def(first[0].not_nil!)
      converter.__test_resolve_call_memo("CallMemoBox#choose", [int32]).should eq(first)
      converter.__test_call_resolution_memo_stats[:hits].should eq(3)
      converter.__test_call_resolution_memo_stats[:misses].should eq(2)
    end

    it "does not reuse a miss across generic contexts" do
      converter = lower_program_with_main("1")
      converter.__test_reset_call_resolution_memo
      no_args = [] of Adamas::HIR::TypeRef
      int_context = {"T" => "Int32"}
      string_context = {"T" => "String"}

      converter.__test_resolve_call_memo("GenericCallMemo#probe", no_args, int_context).should eq({nil, nil})
      converter.__test_resolve_call_memo("GenericCallMemo#probe", no_args, int_context).should eq({nil, nil})
      converter.__test_call_resolution_memo_stats[:hits].should eq(1)
      converter.__test_call_resolution_memo_stats[:misses].should eq(1)

      converter.__test_resolve_call_memo("GenericCallMemo#probe", no_args, string_context).should eq({nil, nil})
      converter.__test_call_resolution_memo_stats[:hits].should eq(1)
      converter.__test_call_resolution_memo_stats[:misses].should eq(2)

      converter.__test_record_class_include_instantiation(
        "GenericCallMemoHost",
        "GenericCallMemoFeature(Int32)",
      )
      converter.__test_resolve_call_memo("GenericCallMemo#probe", no_args, string_context).should eq({nil, nil})
      converter.__test_call_resolution_memo_stats[:hits].should eq(1)
      converter.__test_call_resolution_memo_stats[:misses].should eq(3)
    end

    it "invalidates a cached miss when a module becomes authoritative for the receiver" do
      source = <<-CRYSTAL
        module LateCallMemoFeature
          def probe : Int32
            7
          end
        end

        class LateCallMemoHost
        end

        class LateCallMemoHost
          include LateCallMemoFeature
        end
        CRYSTAL
      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena
      module_node = exprs.compact_map { |id| arena[id].as?(Adamas::Compiler::Frontend::ModuleNode) }.first
      class_nodes = exprs.compact_map { |id| arena[id].as?(Adamas::Compiler::Frontend::ClassNode) }
      converter.register_module(module_node)
      converter.register_class(class_nodes.first)
      converter.__test_reset_call_resolution_memo
      no_args = [] of Adamas::HIR::TypeRef

      converter.__test_resolve_call_memo("LateCallMemoHost#probe", no_args).should eq({nil, nil})
      converter.__test_resolve_call_memo("LateCallMemoHost#probe", no_args).should eq({nil, nil})
      converter.__test_call_resolution_memo_stats[:hits].should eq(1)
      converter.__test_call_resolution_memo_stats[:misses].should eq(1)

      converter.__test_record_module_inclusion("LateCallMemoFeature", "LateCallMemoHost")
      converter.__test_resolve_call_memo("LateCallMemoHost#probe", no_args).should eq({nil, nil})
      converter.__test_call_resolution_memo_stats[:hits].should eq(1)
      converter.__test_call_resolution_memo_stats[:misses].should eq(2)

      converter.register_class(class_nodes.last)
      resolved = converter.__test_resolve_call_memo("LateCallMemoHost#probe", no_args)

      resolved[0].should eq("LateCallMemoHost#probe")
      resolved[1].should_not be_nil
      converter.__test_call_resolution_memo_stats[:hits].should eq(1)
      converter.__test_call_resolution_memo_stats[:misses].should eq(3)
    end
  end

  describe "method-resolution cache identity" do
    it "separates positional and named self-call shapes" do
      converter = lower_program_with_main("1")

      positional = converter.__test_method_resolution_cache_key(false, 0)
      named = converter.__test_method_resolution_cache_key(true, 1, ["value"])
      two_named = converter.__test_method_resolution_cache_key(true, 2)
      other_named = converter.__test_method_resolution_cache_key(true, 1, ["other"])

      positional.should_not eq(named)
      named.should_not eq(two_named)
      named.should_not eq(other_named)
    end

    it "keeps module fanout receiver and argument shapes exact" do
      converter = lower_program_with_main("1")

      int_receiver = converter.__test_module_virtual_fanout_shape_key(
        "Enumerable(Int32)",
        [] of Adamas::HIR::TypeRef,
      )
      string_receiver = converter.__test_module_virtual_fanout_shape_key(
        "Enumerable(String)",
        [] of Adamas::HIR::TypeRef,
      )
      unknown_arg = converter.__test_module_virtual_fanout_shape_key(
        "Enumerable(Int32)",
        [Adamas::HIR::TypeRef::VOID],
      )

      int_receiver.should_not eq(string_receiver)
      int_receiver.should_not eq(unknown_arg)
    end

    it "filters only explicitly incompatible generic module includers" do
      converter = lower_program_with_main(<<-CRYSTAL)
        module TypedRoot(T)
          abstract def probe : T
        end

        class IntOwner
          include TypedRoot(Int32)

          def probe : Int32
            1
          end
        end

        class StringOwner
          include TypedRoot(String)

          def probe : String
            "x"
          end
        end

        class IntParent
          include TypedRoot(Int32)

          def probe : Int32
            2
          end
        end

        class ConflictingChild < IntParent
          include TypedRoot(String)

          def probe : String
            "child"
          end
        end

        IntOwner.new.probe
        StringOwner.new.probe
        ConflictingChild.new.probe
      CRYSTAL

      converter.__test_module_fanout_owner_shape_compatible?(
        "IntOwner",
        "TypedRoot(Int32)",
      ).should be_true
      converter.__test_class_include_instantiations("IntOwner")
        .should contain("TypedRoot(Int32)")
      converter.__test_class_include_instantiations("StringOwner")
        .should contain("TypedRoot(String)")
      converter.__test_module_shape_has_unbound_params?("TypedRoot(Int32)")
        .should be_false
      converter.__test_module_shape_has_unbound_params?("TypedRoot(String)")
        .should be_false
      converter.__test_module_shape_has_unbound_params?("TypedRoot(T)")
        .should be_true
      converter.__test_module_fanout_owner_shape_compatible?(
        "StringOwner",
        "TypedRoot(Int32)",
      ).should be_false
      converter.__test_module_fanout_owner_shape_compatible?(
        "ConflictingChild",
        "TypedRoot(Int32)",
      ).should be_true
      converter.__test_module_fanout_owner_shape_compatible?(
        "MetadataMissingOwner",
        "TypedRoot(Int32)",
      ).should be_true
      converter.__test_module_fanout_owner_shape_compatible?(
        "StringOwner",
        "TypedRoot(T)",
      ).should be_true
    end

    it "invalidates an owner plan when exact include-site metadata changes" do
      converter = lower_program_with_main(<<-CRYSTAL)
        module PlannedRoot(T)
          abstract def probe : T
        end

        class PlannedIntOwner
          include PlannedRoot(Int32)

          def probe : Int32
            1
          end
        end

        class PlannedStringOwner
          include PlannedRoot(String)

          def probe : String
            "x"
          end
        end

        PlannedIntOwner.new.probe
        PlannedStringOwner.new.probe
      CRYSTAL

      before = converter.__test_module_fanout_owner_plan(
        "PlannedRoot",
        "PlannedRoot(Int32)",
      )
      before.should contain("PlannedIntOwner")
      before.should_not contain("PlannedStringOwner")

      converter.__test_record_class_include_instantiation(
        "PlannedStringOwner",
        "PlannedRoot(Int32)",
      )
      after = converter.__test_module_fanout_owner_plan(
        "PlannedRoot",
        "PlannedRoot(Int32)",
      )
      after.should contain("PlannedStringOwner")
    end

    it "does not certify a deferred module virtual target before a retry emits its body" do
      converter = lower_program_with_main(<<-CRYSTAL)
        module RetryRoot
          abstract def probe(value : Int32) : Int32
        end

        class RetryOwner
          include RetryRoot

          def probe(value : Int32) : Int32
            value + 1
          end
        end

        RetryOwner.new.probe(1)
      CRYSTAL

      converter.__test_module_virtual_target_deferred_then_retry(
        "RetryOwner",
        "probe",
        [Adamas::HIR::TypeRef::INT32],
      ).should eq({false, true, true})
    end

    it "preserves exact deferred targets when a DefNode replacement invalidates fanout results" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class ReplacementOwner
          def probe(value : Int32) : Int32
            value
          end

          def alternate(value : Int32) : Int32
            value + 1
          end
        end

        owner = ReplacementOwner.new
        owner.probe(1)
        owner.alternate(1)
      CRYSTAL

      converter.__test_fanout_pending_survives_def_replacement(
        "ReplacementOwner#probe",
        "ReplacementOwner#alternate",
        "probe",
      ).should be_true
    end

    it "invalidates a fanout result when terminal cleanup discards an unresolved candidate" do
      converter = lower_program_with_main("1")

      converter.__test_terminal_fanout_discard_invalidates_result("probe")
        .should eq({1, 0, false, false, true})
    end

    it "stops final missing retries after semantic lowering state reaches a fixed point" do
      converter = lower_program_with_main("1")

      converter.__test_unproductive_fanout_retry_fixed_point("probe")
        .should eq({1, true})

      state_converter = lower_program_with_main("1")
      state_converter.__test_unproductive_fanout_retry_fixed_point("state_probe", "pending")
        .should eq({1, false})

      churn_converter = lower_program_with_main("1")
      churn_converter.__test_unproductive_fanout_retry_fixed_point("churn_probe", "cycle")
        .should eq({1, true})

      snapshot = converter.__test_final_missing_fixed_point_snapshot
      converter.module.create_function(
        "fixed_point_revision_probe",
        Adamas::HIR::TypeRef::VOID,
      )
      converter.__test_final_missing_fixed_point_reached?(snapshot).should be_false

      snapshot = converter.__test_final_missing_fixed_point_snapshot
      converter.__test_record_lowering_demand(
        "queued_fixed_point_probe",
        "spec",
        [] of Adamas::HIR::TypeRef,
      )
      converter.__test_final_missing_fixed_point_reached?(snapshot).should be_false

      snapshot = converter.__test_final_missing_fixed_point_snapshot
      converter.__test_record_class_include_instantiation(
        "FixedPointOwner",
        "FixedPointModule(Int32)",
      )
      converter.__test_final_missing_fixed_point_reached?(snapshot).should be_false
    end

    it "fails closed when final missing lowering exceeds its pass budget" do
      converter = lower_program_with_main("1")

      stable_snapshot = converter.__test_final_missing_fixed_point_snapshot
      converter.__test_final_missing_should_stop?(stable_snapshot, 4).should be_true

      changed_snapshot = converter.__test_final_missing_fixed_point_snapshot
      converter.module.create_function(
        "final_missing_budget_probe",
        Adamas::HIR::TypeRef::VOID,
      )
      converter.__test_final_missing_should_stop?(changed_snapshot, 3).should be_false
      expect_raises(Exception, /final missing lowering did not converge after 4 passes/) do
        converter.__test_final_missing_should_stop?(changed_snapshot, 4)
      end
    end

    it "keeps a concrete bodyless target visible as a fail-closed obligation" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class ConcreteTerminalOwner
          def probe(value : Int32) : Int32
            value + 1
          end
        end

        ConcreteTerminalOwner.new.probe(1)
      CRYSTAL

      converter.__test_terminal_fanout_preserves_concrete_bodyless_target(
        "ConcreteTerminalOwner#probe",
        "probe",
      ).should eq({0, 1, true, false})
    end

  end

  describe "missing-call target batching" do
    it "retains unresolved demands in full-scan order across a bounded batch" do
      converter = lower_program_with_main("1")
      materialized = converter.module.create_function(
        "materialized",
        Adamas::HIR::TypeRef::VOID,
      )
      materialized.get_block(materialized.entry_block).add(
        Adamas::HIR::Literal.new(
          materialized.next_value_id,
          Adamas::HIR::TypeRef::INT32,
          1_i64,
        )
      )
      cached = {
        1_u64 => ["stale"],
        3_u64 => ["removed"],
      }
      current = {
        1_u64 => ["carry", "done"],
        2_u64 => ["new", "carry", "materialized"],
      }
      current_available = {
        1_u64 => ["carry", "done"],
        2_u64 => ["new", "carry"],
      }
      segments, changed = converter.__test_missing_incremental_refresh_segments(
        cached,
        [1_u64, 2_u64],
        current,
      )
      changed.should eq(3)
      cached.keys.sort.should eq([1_u64, 2_u64])
      demands = converter.__test_missing_incremental_flatten_segments(segments)
      available_segments, available_changed =
        converter.__test_missing_incremental_refresh_segments(
          Hash(UInt64, Array(String)).new,
          [1_u64, 2_u64],
          current_available,
        )
      available_changed.should eq(2)
      available =
        converter.__test_missing_incremental_flatten_segments(available_segments)
      available.should eq(["carry", "done", "new"])

      selected, has_more = converter.__test_select_missing_call_target_batch(
        available,
        1,
      )
      selected.should eq(["carry"])
      has_more.should be_true
    end

    it "preserves occurrence-time admission when the target changes later" do
      converter = lower_program_with_main("1")
      target_name = "late_available"
      admitted_segments, changed =
        converter.__test_missing_incremental_refresh_segments(
          Hash(UInt64, Array(String)).new,
          [1_u64],
          {1_u64 => [target_name]},
        )
      changed.should eq(1)

      target = converter.module.create_function(
        target_name,
        Adamas::HIR::TypeRef::VOID,
      )
      target.get_block(target.entry_block).add(
        Adamas::HIR::Literal.new(
          target.next_value_id,
          Adamas::HIR::TypeRef::INT32,
          1_i64,
        )
      )
      converter.__test_missing_incremental_flatten_segments(admitted_segments)
        .should eq([target_name])
      converter.__test_missing_incremental_target_certificate(
        target_name,
        [] of String,
      ).should eq({true, "NotStarted", false})

      first_id = target.id
      converter.module.remove_function(target_name).should be_true
      replacement = converter.module.create_function(
        target_name,
        Adamas::HIR::TypeRef::VOID,
      )
      replacement.id.should_not eq(first_id)
      converter.__test_set_missing_incremental_target_state(target_name, "pending")
      converter.__test_missing_incremental_target_certificate(
        target_name,
        [target_name],
      ).should eq({false, "Pending", true})

      converter.__test_set_missing_incremental_target_state(target_name, "in_progress")
      converter.__test_missing_incremental_target_certificate(
        target_name,
        [target_name],
      ).should eq({false, "InProgress", true})
    end

    it "selects the exact legacy prefix and reports remaining work" do
      converter = lower_program_with_main("1")

      converter.__test_select_missing_call_target_batch(
        ["stuck", "next", "later"],
        1,
      ).should eq({["stuck"], true})
    end

    it "keeps the complete legacy list when the budget is unlimited" do
      converter = lower_program_with_main("1")

      converter.__test_select_missing_call_target_batch(
        ["stuck", "next", "later"],
        0,
      ).should eq({["stuck", "next", "later"], false})
    end

    it "reuses exact segments only while their contents and function order stay equal" do
      converter = lower_program_with_main("1")
      cached = {
        1_u64 => ["first"],
        2_u64 => ["second"],
      }
      current = {
        1_u64 => ["first"],
        2_u64 => ["second"],
      }
      segments, changed = converter.__test_missing_incremental_refresh_segments(
        cached,
        [2_u64, 1_u64],
        current,
      )
      changed.should eq(0)
      converter.__test_missing_incremental_flatten_segments(segments)
        .should eq(["second", "first"])

      current[2_u64] = ["second", "late_missing_target"]
      segments, changed = converter.__test_missing_incremental_refresh_segments(
        cached,
        [2_u64, 1_u64],
        current,
      )
      changed.should eq(1)
      converter.__test_missing_incremental_flatten_segments(segments)
        .should eq(["second", "late_missing_target", "first"])
    end

    it "keeps the legacy no-progress stop with the incremental falsifier off or on" do
      source = "def concrete_tail; 1; end"
      arena, roots = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena

      def_node = roots.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode)
      end.first
      raise "No concrete_tail definition found" unless def_node
      converter.register_function(def_node)

      target_name = converter.__test_function_def_names("concrete_tail").first?
      raise "No registered concrete_tail target" unless target_name

      converter.module.create_function(target_name, Adamas::HIR::TypeRef::INT32)
      converter.module.has_function_with_body?(target_name).should be_false

      driver = converter.module.create_function("__test_missing_budget_driver", Adamas::HIR::TypeRef::VOID)
      block = driver.get_block(driver.entry_block)
      34.times do |index|
        block.add(
          Adamas::HIR::Call.without_receiver(
            driver.next_value_id,
            Adamas::HIR::TypeRef::VOID,
            "missing_budget_head_#{index}",
            [] of Adamas::HIR::ValueId,
          )
        )
      end
      block.add(
        Adamas::HIR::Call.without_receiver(
          driver.next_value_id,
          Adamas::HIR::TypeRef::INT32,
          target_name,
          [] of Adamas::HIR::ValueId,
        )
      )

      previous_falsifier = ENV["ADAMAS_MISSING_INCREMENTAL_FALSIFIER"]?
      begin
        ENV.delete("ADAMAS_MISSING_INCREMENTAL_FALSIFIER")
        converter.__test_lower_missing_call_targets_with_budget(34)
        converter.module.has_function_with_body?(target_name).should be_false

        ENV["ADAMAS_MISSING_INCREMENTAL_FALSIFIER"] = "1"
        converter.__test_lower_missing_call_targets_with_budget(34)
        converter.module.has_function_with_body?(target_name).should be_false
      ensure
        if previous_falsifier
          ENV["ADAMAS_MISSING_INCREMENTAL_FALSIFIER"] = previous_falsifier
        else
          ENV.delete("ADAMAS_MISSING_INCREMENTAL_FALSIFIER")
        end
      end
    end
  end

  describe "receiver-repair target fallback" do
    it "does not lower a base fallback after the exact target materializes" do
      source = <<-CRYSTAL
        def exact_receiver_target : Int32
          1
        end

        def fallback_receiver_target : Int32
          2
        end
      CRYSTAL
      arena, roots = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena
      roots.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode)
      end.each { |def_node| converter.register_function(def_node) }

      exact = converter.__test_function_def_names("exact_receiver_target").first
      fallback = converter.__test_function_def_names("fallback_receiver_target").first
      converter.__test_lower_receiver_repair_target_with_fallback(exact, fallback)
        .should eq({true, false})
    end

    it "fails closed when fallback lowering cannot materialize a direct exact target" do
      source = <<-CRYSTAL
        def fallback_receiver_target : Int32
          2
        end
      CRYSTAL
      arena, roots = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena
      roots.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode)
      end.each { |def_node| converter.register_function(def_node) }

      exact = "MissingReceiver#target$Int32"
      fallback = converter.__test_function_def_names("fallback_receiver_target").first
      converter.module.create_function(exact, Adamas::HIR::TypeRef::INT32)
      expect_raises(Exception, /receiver repair left bodyless target/) do
        converter.__test_lower_receiver_repair_target_with_fallback(exact, fallback)
      end
      converter.module.has_function_with_body?(exact).should be_false
      converter.module.has_function_with_body?(fallback).should be_true
    end

    it "fails closed when a registered generic setter cannot materialize its exact ABI" do
      expect_raises(Exception, /receiver repair left bodyless target GenericSetter.*#\[\]=\$String_NamedTuple/) do
        converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
          class GenericSetter(T)
            def []=(key : String, value : T) : T
              value
            end
          end

          class BareNamedTupleSetterProbe
            @@entries = GenericSetter(NamedTuple(name: String, count: Int32)).new

            def self.entry : NamedTuple
              {name: "probe", count: 1}
            end

            def self.store
              @@entries["probe"] = entry
            end
          end

          BareNamedTupleSetterProbe.store
        CRYSTAL
        converter.__test_repair_receiver_bound_call_targets
      end
    end

    it "does not demand an incompatible sibling overload from a shared fallback base" do
      source = <<-CRYSTAL
        class ReceiverOverloads
          def target(value : Int32) : Int32
            value
          end
        end
      CRYSTAL
      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena
      exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
      end.each { |node| converter.register_class(node) }

      converter.__test_receiver_repair_strict_target_expected(
        "ReceiverOverloads#target$String",
        "ReceiverOverloads#target",
        "ReceiverOverloads",
        [Adamas::HIR::TypeRef::STRING],
      ).should be_false
    end

    it "does not demand a generic template with incompatible owner bindings" do
      source = <<-CRYSTAL
        class GenericReceiver(T)
          def target(value : T) : T
            value
          end
        end
      CRYSTAL
      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena
      exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
      end.each { |node| converter.register_class(node) }

      converter.__test_receiver_repair_strict_target_expected(
        "GenericReceiver(String)#target$Bool",
        "GenericReceiver(String)#target",
        "GenericReceiver(String)",
        [Adamas::HIR::TypeRef::BOOL],
      ).should be_false
    end

    it "does not treat a bare generic argument as a shaped union" do
      source = <<-CRYSTAL
        class GenericReceiver(T)
          def target(value : T) : T
            value
          end
        end
      CRYSTAL
      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena
      exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
      end.each { |node| converter.register_class(node) }

      owner = "GenericReceiver(Array(Int32) | String)"
      converter.__test_receiver_repair_strict_target_expected(
        "#{owner}#target$Array",
        "#{owner}#target",
        owner,
        [converter.__test_type_ref_for_name("Array")],
      ).should be_false
    end

    it "does not mix generic owner bindings across receiver-repair inputs" do
      source = <<-CRYSTAL
        class GenericReceiver(T)
          def target(value : T) : T
            value
          end
        end
      CRYSTAL
      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena
      exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
      end.each { |node| converter.register_class(node) }

      converter.__test_receiver_repair_strict_target_expected(
        "GenericReceiver(String)#target$Int32",
        "GenericReceiver(String)#target",
        "GenericReceiver(Int32)",
        [Adamas::HIR::TypeRef::INT32],
      ).should be_false
    end

    it "does not mix an exact target with a sibling generic owner" do
      source = <<-CRYSTAL
        class GenericReceiver(T)
          def target(value : T) : T
            value
          end
        end
      CRYSTAL
      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena
      exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
      end.each { |node| converter.register_class(node) }

      converter.__test_receiver_repair_strict_target_expected(
        "GenericReceiver(Int32)#target$String",
        "GenericReceiver(String)#target",
        "GenericReceiver(String)",
        [Adamas::HIR::TypeRef::STRING],
      ).should be_false
    end

    it "does not demand an abstract generic template body" do
      source = <<-CRYSTAL
        abstract class AbstractGenericReceiver(T)
          abstract def target(value : T) : T
        end
      CRYSTAL
      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena
      exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
      end.each { |node| converter.register_class(node) }

      converter.__test_receiver_repair_strict_target_expected(
        "AbstractGenericReceiver(String)#target$String",
        "AbstractGenericReceiver(String)#target",
        "AbstractGenericReceiver(String)",
        [Adamas::HIR::TypeRef::STRING],
      ).should be_false
    end

    it "materializes both direct overload shapes that share one fallback base" do
      source = <<-CRYSTAL
        class ReceiverOverloads
          def target(value : Int32) : Int32
            value
          end

          def target(value : String) : String
            value
          end
        end
      CRYSTAL
      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena
      exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
      end.each { |node| converter.register_class(node) }

      int_target = "ReceiverOverloads#target$Int32"
      string_target = "ReceiverOverloads#target$String"
      base = "ReceiverOverloads#target"
      converter.__test_lower_receiver_repair_targets_with_fallbacks([
        {int_target, base, [Adamas::HIR::TypeRef::INT32]},
        {string_target, base, [Adamas::HIR::TypeRef::STRING]},
      ])

      int_body = converter.module.function_by_name(int_target)
      string_body = converter.module.function_by_name(string_target)
      int_body.should_not be_nil
      string_body.should_not be_nil
      converter.module.has_function_with_body?(int_target).should be_true
      converter.module.has_function_with_body?(string_target).should be_true
      int_body.not_nil!.params.last.type.should eq(Adamas::HIR::TypeRef::INT32)
      string_body.not_nil!.params.last.type.should eq(Adamas::HIR::TypeRef::STRING)
    end

    it "preserves a concrete generic owner before considering its inherited base" do
      source = <<-CRYSTAL
        module Runner(T)
          def run(value : T) : T
            value
          end
        end

        class Parent
          include Runner(Int32)
        end

        class Box(T) < Parent
        end

        def invoke(io : Parent, value : Int32) : Int32
          io.run(value)
        end
      CRYSTAL
      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena
      exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ModuleNode)
      end.each { |node| converter.register_module(node) }
      exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
      end.each { |node| converter.register_class(node) }
      def_nodes = exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode)
      end
      def_nodes.each { |node| converter.register_function(node) }
      converter.__test_monomorphize_generic_class("Box", ["Int32"], "Box(Int32)")
      converter.lower_def(def_nodes.first)

      exact = converter.module.functions.find { |func| func.name.starts_with?("Box(Int32)#run$") }
      exact.should_not be_nil
      exact_name = exact.not_nil!.name
      converter.module.remove_function(exact_name).should be_true
      converter.__test_reset_lowering_state(exact_name)

      converter.__test_lower_receiver_repair_target_with_fallback(exact_name, "Parent#run")
        .should eq({true, false})
      converter.__test_get_type_name_from_ref(
        converter.module.function_by_name(exact_name).not_nil!.return_type
      ).should eq("Int32")
    end

    it "does not turn a nested generic declaration into a reopening per parent specialization" do
      source = <<-CRYSTAL
        class NestedGenericOwner(T)
          struct Entry(U)
            def initialize(@value : U)
            end
          end
        end
      CRYSTAL
      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena
      exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
      end.each { |node| converter.register_class(node) }

      converter.__test_generic_reopening_count("NestedGenericOwner::Entry").should eq(0)
      converter.__test_monomorphize_generic_class(
        "NestedGenericOwner",
        ["Int32"],
        "NestedGenericOwner(Int32)",
      )
      converter.__test_monomorphize_generic_class(
        "NestedGenericOwner",
        ["String"],
        "NestedGenericOwner(String)",
      )

      converter.__test_generic_reopening_count("NestedGenericOwner::Entry").should eq(0)
    end

    it "registers nested module generic declarations once while preserving source reopenings" do
      source = <<-CRYSTAL
        module NestedModuleReplayOwner
          module Types
            class Single(T)
            end

            class Reopened(T)
              def first : Int32
                1
              end
            end

            class Reopened(T)
              def second : Int32
                2
              end
            end
          end
        end
      CRYSTAL
      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena
      exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ModuleNode)
      end.each { |node| converter.register_module(node) }

      converter.__test_generic_reopening_count(
        "NestedModuleReplayOwner::Types::Single"
      ).should eq(0)
      converter.__test_generic_reopening_count(
        "NestedModuleReplayOwner::Types::Reopened"
      ).should eq(1)
    end

    it "stores exact nested module declarations once while preserving source reopenings" do
      source = <<-CRYSTAL
        module ExactModuleReplayOwner
          module Single
          end

          module Reopened
            def self.first : Int32
              1
            end
          end

          module Reopened
            def self.second : Int32
              2
            end
          end
        end
      CRYSTAL
      arena, exprs = parse(source)
      owner = exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ModuleNode)
      end.first
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena

      converter.register_module(owner)
      version_after_first_registration = converter.__test_module_defs_cache_version
      converter.register_module(owner)

      converter.__test_module_defs_cache_version.should eq(version_after_first_registration)
      converter.__test_module_def_count(
        "ExactModuleReplayOwner::Single"
      ).should eq(1)
      converter.__test_module_def_count(
        "ExactModuleReplayOwner::Reopened"
      ).should eq(2)
    end

    it "replays a concrete class after a later nested struct resolves its inline layout" do
      source = <<-CRYSTAL
        module LateStructReplayOwner
          class Probe
            @slot : Later
          end
        end

        module LateStructReplayOwner
          struct Later
            @left : Int64
            @right : Int64
          end
        end
      CRYSTAL
      arena, exprs = parse(source)
      modules = exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ModuleNode)
      end
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena

      converter.register_module(modules.first)
      before_size = converter.class_info["LateStructReplayOwner::Probe"].size

      converter.register_module(modules.last)
      converter.register_module(modules.first)

      after_size = converter.class_info["LateStructReplayOwner::Probe"].size
      after_size.should be > before_size
    end

    it "refreshes a cached module-method miss after a late include alias" do
      source = <<-CRYSTAL
        module LateIncludeAliasOwner
          include LateIncludeAlias
        end

        module LateIncludeAliasTarget
          def probe : Int32
            1
          end
        end

        alias LateIncludeAlias = LateIncludeAliasTarget
      CRYSTAL
      arena, exprs = parse(source)
      modules = exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ModuleNode)
      end
      alias_node = exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::AliasNode)
      end.first
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena

      converter.register_module(modules.first)
      converter.register_module(modules.last)
      converter.__test_has_module_def_recursive?(
        "LateIncludeAliasOwner",
        "probe",
      ).should be_false

      converter.register_alias(alias_node)
      converter.register_module(modules.first)

      converter.__test_has_module_def_recursive?(
        "LateIncludeAliasOwner",
        "probe",
      ).should be_true
    end

  end

  describe "protected access through included modules" do
    it "treats absolute and relative spellings of the same generic owner as identical" do
      arena, _ = parse("1")
      converter = Adamas::HIR::AstToHir.new(arena)

      converter.__test_has_protected_access_to(
        "::Hash(String, Int32)",
        "Hash(String, Int32)",
      ).should be_true
      converter.__test_has_protected_access_to(
        "Hash(String, Int32)",
        "::Hash(String, Int32)",
      ).should be_true
      converter.__test_has_protected_access_to(
        "::Array(String)",
        "Hash(String, Int32)",
      ).should be_false
    end

    it "allows an included module singleton method to call the owner's protected method" do
      converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
        module WorkerSystem
          def self.run(worker : Worker) : Nil
            worker.start
          end
        end

        class Worker
          include WorkerSystem

          protected def start : Nil
          end
        end

        WorkerSystem.run(Worker.new)
      CRYSTAL

      converter.module.function_by_name("WorkerSystem.run$Worker").should_not be_nil
    end

    it "rejects the same protected call from an unrelated module" do
      expect_raises(Adamas::HIR::LoweringError, /protected method 'start'/) do
        lower_program_with_main(<<-CRYSTAL, source_backed: true)
          module StrangerSystem
            def self.run(worker : Worker) : Nil
              worker.start
            end
          end

          class Worker
            protected def start : Nil
            end
          end

          StrangerSystem.run(Worker.new)
        CRYSTAL
      end
    end
  end

  describe "macro-expanded explicit return contracts" do
    it "lets a later same-signature expansion replace the current return contract" do
      source = <<-CRYSTAL
        macro define_contract(return_type)
          def stable_name(value : Bool) : {{return_type.id}}
            value
          end
        end

        class MacroSameSignatureContract
          define_contract String
          define_contract Int32
        end
      CRYSTAL
      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena
      macro_node = exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::MacroDefNode)
      end.first
      class_node = exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
      end.first

      converter.register_macro(macro_node)
      converter.register_class(class_node)

      return_type = converter.__test_get_function_return_type(
        "MacroSameSignatureContract#stable_name$Bool"
      )
      converter.__test_get_type_name_from_ref(return_type).should eq("Int32")

      converter.lower_class(class_node)
      lowered = converter.module.function_by_name(
        "MacroSameSignatureContract#stable_name$Bool"
      )
      lowered.should_not be_nil
      converter.__test_get_type_name_from_ref(
        lowered.not_nil!.return_type
      ).should eq("Int32")
    end

    it "lowers the latest same-signature expansion body" do
      source = <<-CRYSTAL
        macro define_body(result)
          def stable_body(value : Bool) : Int32
            {{result}}
          end
        end

        class MacroSameSignatureBody
          define_body 11
          define_body 22
        end
      CRYSTAL
      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena
      macro_node = exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::MacroDefNode)
      end.first
      class_node = exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
      end.first

      converter.register_macro(macro_node)
      converter.register_class(class_node)
      converter.lower_class(class_node)

      lowered = converter.module.function_by_name(
        "MacroSameSignatureBody#stable_body$Bool"
      )
      lowered.should_not be_nil
      literals = lowered.not_nil!.blocks.flat_map(&.instructions)
        .select { |inst| inst.is_a?(Adamas::HIR::Literal) }
        .map { |inst| inst.as(Adamas::HIR::Literal).value }
      literals.includes?(22_i64).should be_true
      literals.includes?(11_i64).should be_false
    end
  end

  describe "macro-expanded initializer parameter capture" do
    it "refines an untyped initializer ivar from a typed macro accessor" do
      source = <<-CRYSTAL
        macro add_accessor
          getter value : String
        end

        class MacroAccessorOwner
          def initialize(@value)
          end

          add_accessor()
        end
      CRYSTAL
      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena
      macro_node = exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::MacroDefNode)
      end.first
      class_node = exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
      end.first

      converter.register_macro(macro_node)
      converter.register_class(class_node)

      value_ivar = converter.class_info["MacroAccessorOwner"].ivars.find do |ivar|
        ivar.name == "@value"
      end
      value_ivar.should_not be_nil
      converter.__test_get_type_name_from_ref(value_ivar.not_nil!.type).should eq("String")
    end

    it "materializes a nested macro accessor with its concrete value ABI" do
      source = <<-CRYSTAL
        macro add_accessor
          getter count : Int32
        end

        class MacroIntAccessorOwner
          def initialize(@count)
          end

          add_accessor()
        end
      CRYSTAL
      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena
      macro_node = exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::MacroDefNode)
      end.first
      class_node = exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
      end.first

      converter.register_macro(macro_node)
      converter.register_class(class_node)
      converter.lower_class(class_node)

      count_ivar = converter.class_info["MacroIntAccessorOwner"].ivars.find do |ivar|
        ivar.name == "@count"
      end
      count_ivar.should_not be_nil
      count_ivar.not_nil!.type.should eq(Adamas::HIR::TypeRef::INT32)

      getter = converter.module.function_by_name("MacroIntAccessorOwner#count")
      getter.should_not be_nil
      getter.not_nil!.return_type.should eq(Adamas::HIR::TypeRef::INT32)
      hir_text(getter.not_nil!).should contain("field_get")
    end

    it "materializes a nested predicate accessor as Bool" do
      source = <<-CRYSTAL
        macro add_predicate
          getter? ready : Bool
        end

        class MacroPredicateAccessorOwner
          def initialize(@ready)
          end

          add_predicate()
        end
      CRYSTAL
      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena
      macro_node = exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::MacroDefNode)
      end.first
      class_node = exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
      end.first

      converter.register_macro(macro_node)
      converter.register_class(class_node)
      converter.lower_class(class_node)

      ready_ivar = converter.class_info["MacroPredicateAccessorOwner"].ivars.find do |ivar|
        ivar.name == "@ready"
      end
      ready_ivar.should_not be_nil
      ready_ivar.not_nil!.type.should eq(Adamas::HIR::TypeRef::BOOL)

      getter = converter.module.function_by_name("MacroPredicateAccessorOwner#ready?")
      getter.should_not be_nil
      getter.not_nil!.return_type.should eq(Adamas::HIR::TypeRef::BOOL)
      hir_text(getter.not_nil!).should contain("field_get")
    end

    it "materializes both sides of a nested typed property" do
      source = <<-CRYSTAL
        macro add_property
          property level : Int32
        end

        class MacroPropertyAccessorOwner
          def initialize(@level)
          end

          add_property()
        end
      CRYSTAL
      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena
      macro_node = exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::MacroDefNode)
      end.first
      class_node = exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
      end.first

      converter.register_macro(macro_node)
      converter.register_class(class_node)
      converter.lower_class(class_node)

      level_ivar = converter.class_info["MacroPropertyAccessorOwner"].ivars.find do |ivar|
        ivar.name == "@level"
      end
      level_ivar.should_not be_nil
      level_ivar.not_nil!.type.should eq(Adamas::HIR::TypeRef::INT32)

      getter = converter.module.function_by_name("MacroPropertyAccessorOwner#level")
      setter = converter.module.function_by_name("MacroPropertyAccessorOwner#level=$Int32")
      getter.should_not be_nil
      setter.should_not be_nil
      getter.not_nil!.return_type.should eq(Adamas::HIR::TypeRef::INT32)
      setter.not_nil!.return_type.should eq(Adamas::HIR::TypeRef::INT32)
      hir_text(getter.not_nil!).should contain("field_get")
      hir_text(setter.not_nil!).should contain("field_set")
    end

    it "rejects nested accessor shapes without a proven storage ABI" do
      source = <<-CRYSTAL
        macro add_untyped_accessor
          getter value
        end

        class UnsupportedNestedAccessorOwner
          def initialize(@value)
          end

          add_untyped_accessor()
        end
      CRYSTAL
      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena
      macro_node = exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::MacroDefNode)
      end.first
      class_node = exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
      end.first

      converter.register_macro(macro_node)
      expect_raises(Exception, /unsupported nested accessor macro output/) do
        converter.register_class(class_node)
      end
    end

    it "keeps an unannotated captured block as a Proc ABI parameter" do
      source = <<-CRYSTAL
        class UntypedBlockCapture
          def initialize(&@proc)
          end
        end
      CRYSTAL
      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena
      class_node = exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
      end.first

      converter.register_class(class_node)

      params = converter.__test_initializer_params("UntypedBlockCapture")
      params.map(&.[0]).should eq(["proc"])
      params.map(&.[1]).should eq(["Proc"])
      proc_ivar = converter.class_info["UntypedBlockCapture"].ivars.find do |ivar|
        ivar.name == "@proc"
      end
      proc_ivar.should_not be_nil
      converter.__test_get_type_name_from_ref(proc_ivar.not_nil!.type).should eq("Proc")
    end

    it "keeps a block constructor call on its class allocator" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class CompetingBlockConstructor
          def self.new(&block)
            block
          end
        end

        class UntypedBlockRuntime
          def initialize(&@proc)
          end

          def run
            @proc.call
          end
        end

        def consume(value)
          value
        end

        consume((UntypedBlockRuntime.new { 42 }).run)
      CRYSTAL

      main = converter.module.function_by_name("__adamas_main")
      main.should_not be_nil
      main_text = hir_text(main.not_nil!)
      main_text.should contain("UntypedBlockRuntime.new")
      main_text.should_not contain("call Proc.new$block")

      initializer = converter.module.function_by_name(
        "UntypedBlockRuntime#initialize$block"
      )
      initializer.should_not be_nil
      converter.__test_get_type_name_from_ref(
        initializer.not_nil!.params.last.type
      ).should eq("Proc")
      hir_text(initializer.not_nil!).should_not contain("make_proc")

      proc_ivar = converter.class_info["UntypedBlockRuntime"].ivars.find do |ivar|
        ivar.name == "@proc"
      end
      proc_ivar.should_not be_nil
      proc_desc = converter.module.get_type_descriptor(proc_ivar.not_nil!.type)
      proc_desc.should_not be_nil
      proc_desc.not_nil!.type_params.last.should eq(Adamas::HIR::TypeRef::INT32)

      run = converter.module.function_by_name("UntypedBlockRuntime#run")
      run.should_not be_nil
      run.not_nil!.return_type.should eq(Adamas::HIR::TypeRef::INT32)
    end

    it "refines a captured Proc reader on the inherited initializer owner" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class InheritedProcBase
          def initialize(&@proc)
          end

          def run
            @proc.call
          end
        end

        class InheritedProcChild < InheritedProcBase
        end

        def consume(value)
          value
        end

        consume((InheritedProcChild.new { 42 }).run)
      CRYSTAL

      base_ivar = converter.class_info["InheritedProcBase"].ivars.find do |ivar|
        ivar.name == "@proc"
      end
      child_ivar = converter.class_info["InheritedProcChild"].ivars.find do |ivar|
        ivar.name == "@proc"
      end
      base_ivar.should_not be_nil
      child_ivar.should_not be_nil
      base_desc = converter.module.get_type_descriptor(base_ivar.not_nil!.type)
      child_desc = converter.module.get_type_descriptor(child_ivar.not_nil!.type)
      base_desc.should_not be_nil
      child_desc.should_not be_nil
      base_desc.not_nil!.type_params.last.should eq(Adamas::HIR::TypeRef::INT32)
      child_desc.not_nil!.type_params.last.should eq(Adamas::HIR::TypeRef::INT32)

      run = converter.module.function_by_name("InheritedProcBase#run")
      run.should_not be_nil
      run.not_nil!.return_type.should eq(Adamas::HIR::TypeRef::INT32)
    end

    it "rejects incompatible captured Proc return ABIs" do
      source = <<-CRYSTAL
        class ConflictingProcCapture
          def initialize(&@proc)
          end

          def run
            @proc.call
          end
        end
      CRYSTAL
      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena
      class_node = exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
      end.first
      converter.register_class(class_node)

      converter.__test_refine_captured_initializer_proc_type(
        "ConflictingProcCapture",
        "Proc(Int32)",
        "Int32",
      )
      expect_raises(Exception, /captured initializer Proc ABI conflict/) do
        converter.__test_refine_captured_initializer_proc_type(
          "ConflictingProcCapture",
          "Proc(String)",
          "String",
        )
      end
    end

    it "does not recover generated parameter spans from the enclosing source" do
      source = <<-CRYSTAL
        # deliberately long prefix whose offsets overlap the generated def
        class MacroInitializerCapture
          class Stack
          end

          {% begin %}
          def initialize(@name : String?, @stack : Stack, &@proc : ->)
          end
          {% end %}
        end
      CRYSTAL
      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena
      class_node = exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
      end.first

      converter.register_class(class_node)

      params = converter.__test_initializer_params("MacroInitializerCapture")
      params.map(&.[0]).should eq(["name", "stack", "proc"])
      params[0][1].should eq("Nil | String")
      params[1][1].should eq("MacroInitializerCapture::Stack")

      converter.__test_function_def_names(
        "MacroInitializerCapture#initialize"
      ).should contain(
        "MacroInitializerCapture#initialize$Nil | String_MacroInitializerCapture::Stack_block"
      )
    end

    it "captures a generated ordinary initializer from retained macro output" do
      source = <<-CRYSTAL
        # Keep the generated parameter span unrelated to the enclosing source.
        class MacroNoIvarInitializer
          {% begin %}
          def initialize(value : Int32)
          end
          {% end %}
        end
      CRYSTAL
      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena
      class_node = exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
      end.first

      converter.register_class(class_node)

      converter.__test_initializer_params("MacroNoIvarInitializer").should eq([
        {"value", "Int32"},
      ])
      converter.__test_function_def_names(
        "MacroNoIvarInitializer#initialize"
      ).should contain("MacroNoIvarInitializer#initialize$Int32")
    end

    it "does not trust same-arena retained foreign raw slices for ordinary initialization" do
      source = <<-CRYSTAL
        class OrdinaryRetainedForeignInitializer
          def initialize(value : Int32)
          end
        end
      CRYSTAL
      arena, exprs = parse(source)
      class_node = exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
      end.first
      initialize_node = class_node.body.not_nil!.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode)
      end.find { |node| String.new(node.name.not_nil!) == "initialize" }
      initialize_node.should_not be_nil

      # Reparse an unrelated signature into the same arena. The existing-arena
      # parser retains this buffer, so copying its token slices reproduces the
      # stale foreign payload while the original spans still point at `value`
      # and `Int32` in the source-backed class.
      foreign_source = "def generated(other : String)\nend\n"
      foreign_parser = Adamas::Compiler::Frontend::Parser.new(
        Adamas::Compiler::Frontend::Lexer.new(foreign_source),
        arena,
        recovery_mode: true,
      )
      foreign_program = foreign_parser.parse_program
      foreign_node = foreign_program.roots.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode)
      end.first
      foreign_node.should_not be_nil
      foreign_param = foreign_node.params.not_nil!.first
      original_param = initialize_node.not_nil!.params.not_nil!.first
      initialize_node.not_nil!.params.not_nil![0] = Adamas::Compiler::Frontend::Parameter.new(
        foreign_param.name,
        original_param.external_name,
        foreign_param.type_annotation,
        original_param.default_value,
        original_param.span,
        original_param.name_span,
        original_param.external_name_span,
        original_param.type_span,
        original_param.default_span,
        original_param.is_splat,
        original_param.is_double_splat,
        original_param.is_block,
        original_param.is_instance_var,
      )

      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena
      # Converter-side extras make source recovery fail closed, matching the
      # ambiguous retained-buffer state seen during self-hosted macro replay.
      converter.__test_store_extra_source(arena, foreign_source)
      converter.register_class(class_node)

      converter.__test_initializer_params(
        "OrdinaryRetainedForeignInitializer"
      ).should eq([{"value", "Int32"}])
      converter.__test_function_def_names(
        "OrdinaryRetainedForeignInitializer#initialize"
      ).should contain(
        "OrdinaryRetainedForeignInitializer#initialize$Int32"
      )
      converter.__test_function_def_names(
        "OrdinaryRetainedForeignInitializer#initialize$String"
      ).should be_empty
    end

    it "requires an exact source certificate for generated parameter recovery" do
      source = "def initialize(@value : Int32)\nend\n"
      foreign_source = "def initialize(@wrong : UInt8)\nend\n"
      source.bytesize.should eq(foreign_source.bytesize)

      arena, exprs = parse(source)
      initialize_node = exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode)
      end.first

      converter = Adamas::HIR::AstToHir.new(arena)
      converter.arena = arena
      converter.__test_store_extra_source(arena, source)
      converter.__test_store_extra_source(arena, foreign_source)

      converter.__test_macro_generated_ivar_param_entries(
        initialize_node,
        arena,
        "initialize",
      ).should be_nil

      converter.__test_remember_macro_generated_parameter_sources(
        exprs.first,
        arena,
        source,
      )
      foreign_arena, _ = parse(foreign_source)
      converter.__test_macro_generated_ivar_param_entries(
        initialize_node,
        foreign_arena,
        "initialize",
      ).should be_nil
      converter.__test_macro_generated_ivar_param_entries(
        initialize_node,
        arena,
        "initialize",
      ).should eq([{"value", "Int32"}])
    end

    it "keeps ordinary parameter identity when only parser-retained source is available" do
      source = <<-CRYSTAL
        class RetainedOnlyInitializer
          def initialize(value : Int32, &@proc : ->)
          end
        end
      CRYSTAL
      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(arena)
      converter.arena = arena
      class_node = exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
      end.first

      converter.register_class(class_node)

      params = converter.__test_initializer_params("RetainedOnlyInitializer")
      params.map(&.[0]).should eq(["value", "proc"])
      params.map { |entry| entry[1] }.should eq(["Int32", "Proc"])
      converter.__test_function_def_names(
        "RetainedOnlyInitializer#initialize"
      ).should contain(
        "RetainedOnlyInitializer#initialize$Int32_block"
      )
    end

    it "rechecks cached retained-source provenance after sources are appended" do
      source = "def source(value : Int32)\nend\n"
      foreign_source = "def generated(other : String)\nend\n"
      mapped_source = "def mapped(flag : Bool)\nend\n"
      arena, _ = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )

      slice = foreign_source.to_slice
      converter.__test_parameter_slice_from_foreign_retained_source?(slice, arena).should be_false

      arena.retain_source(foreign_source)
      converter.__test_parameter_slice_from_foreign_retained_source?(slice, arena).should be_true

      mapped_slice = mapped_source.to_slice
      converter.__test_parameter_slice_from_foreign_retained_source?(mapped_slice, arena).should be_false

      converter.__test_store_extra_source(arena, mapped_source)
      converter.__test_parameter_slice_from_foreign_retained_source?(mapped_slice, arena).should be_true
    end

    it "rechecks cached retained-source provenance after same-size source replacement" do
      source = "def source(value : Int32)\nend\n"
      replacement = String.new(source.to_slice)
      arena, _ = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )

      slice = source.to_slice
      converter.__test_parameter_slice_from_foreign_retained_source?(slice, arena).should be_false

      converter.__test_set_source_for_arena(arena, replacement)
      converter.__test_parameter_slice_from_foreign_retained_source?(slice, arena).should be_true
    end

    it "binds a forwarded Proc constructor wrapper to the macro block initializer" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class MacroForwardedBlockInitializer
          class Stack
          end

          {% begin %}
          def initialize(@name : String?, @stack : Stack, &@proc : ->)
            11
          end
          {% end %}

          def initialize(stack : Pointer(Void), thread : Stack)
            22
          end
        end

        MacroForwardedBlockInitializer.new(
          nil,
          MacroForwardedBlockInitializer::Stack.new,
          -> { nil },
        )
      CRYSTAL

      allocator = converter.module.functions.find do |function|
        function.name.starts_with?("MacroForwardedBlockInitializer.new$") &&
          function.name.ends_with?("_Proc")
      end
      allocator.should_not be_nil

      initializer_call = allocator.not_nil!.blocks
        .flat_map(&.instructions)
        .compact_map(&.as?(Adamas::HIR::Call))
        .find { |call| call.method_name.starts_with?("MacroForwardedBlockInitializer#initialize") }
      initializer_call.should_not be_nil
      initializer_call.not_nil!.method_name.should start_with(
        "MacroForwardedBlockInitializer#initialize$"
      )
      initializer_call.not_nil!.method_name.should end_with("_block")

      initializer = converter.module.function_by_name(initializer_call.not_nil!.method_name)
      initializer.should_not be_nil
      literals = initializer.not_nil!.blocks.flat_map(&.instructions)
        .select { |instruction| instruction.is_a?(Adamas::HIR::Literal) }
        .map { |instruction| instruction.as(Adamas::HIR::Literal).value }
      literals.includes?(11_i64).should be_true
      literals.includes?(22_i64).should be_false
    end
  end

  describe "slice hardening" do
    it "returns nil for unreadable slices instead of crashing" do
      arena, _ = parse("def foo; 1; end")
      converter = Adamas::HIR::AstToHir.new(arena)
      bogus = Slice.new(Pointer(UInt8).new(0x6e6f6974_u64), 4)

      converter.__test_safe_slice_to_string(bogus).should be_nil
    end

    it "accepts heap-backed slices while rejecting null and low pointers" do
      arena, _ = parse("def foo; 1; end")
      converter = Adamas::HIR::AstToHir.new(arena)
      valid = "heap-backed".to_slice
      null_slice = Slice.new(Pointer(UInt8).null, 0)
      low_slice = Slice.new(Pointer(UInt8).new(1_u64), 1)

      converter.__test_safe_slice_guard?(valid).should be_true
      converter.__test_safe_slice_guard?(null_slice).should be_false
      converter.__test_safe_slice_guard?(low_slice).should be_false
    end
  end

  describe "intrinsic block parameter binding" do
    it "binds the block parameter to the Int32 counter phi" do
      converter = lower_program_with_sources(<<-CRYSTAL)
        def probe
          16.times { |index| index.to_u32 }
        end
      CRYSTAL

      function = converter.module.function_by_name("probe")
      function.should_not be_nil
      text = hir_text(function.not_nil!)
      text.should_not contain("local \"index\" : Void")
      text.should_not contain("local \"index\" : 0")
      text.should contain("cast")
    end

    it "uses the block owner arena when the ambient arena is foreign" do
      owner_arena, owner_exprs = parse("16.times { |index| index.to_u32 }")
      call = owner_arena[owner_exprs.first].as(Adamas::Compiler::Frontend::CallNode)
      block = owner_arena[call.block.not_nil!].as(Adamas::Compiler::Frontend::BlockNode)

      foreign_arena, _ = parse(<<-CRYSTAL)
        alpha = 1
        beta = 2
        gamma = 3
        delta = 4
        epsilon = 5
        zeta = 6
        eta = 7
        theta = 8
      CRYSTAL

      converter = Adamas::HIR::AstToHir.new(owner_arena)
      function = converter.__test_lower_times_with_foreign_current_arena(block, owner_arena, foreign_arena)
      text = hir_text(function)
      text.should_not contain("local \"index\" : Void")
      text.should_not contain("local \"index\" : 0")
      text.should contain("cast")
    end

    it "recovers the block parameter key from source when its raw slice is stale" do
      source = "16.times { |index| index.to_u32 }"
      owner_arena, owner_exprs = parse(source)
      call = owner_arena[owner_exprs.first].as(Adamas::Compiler::Frontend::CallNode)
      block = owner_arena[call.block.not_nil!].as(Adamas::Compiler::Frontend::BlockNode)
      original_param = block.params.not_nil!.first
      stale_param = Adamas::Compiler::Frontend::Parameter.new(
        "wrong".to_slice,
        span: original_param.span,
        name_span: original_param.name_span,
      )
      block.params.not_nil![0] = stale_param

      sources = {owner_arena.object_id.to_u64 => source}
      converter = Adamas::HIR::AstToHir.new(owner_arena, sources_by_arena: sources)
      function = converter.__test_lower_times_with_foreign_current_arena(block, owner_arena, owner_arena)
      text = hir_text(function)
      text.should_not contain("local \"index\" : Void")
      text.should_not contain("local \"index\" : 0")
      text.should contain("cast")
    end

    it "recovers dynamic Array#each parameter keys from source" do
      source = "values.each { |elem| elem.to_u32 }"
      owner_arena, owner_exprs = parse(source)
      call = owner_arena[owner_exprs.first].as(Adamas::Compiler::Frontend::CallNode)
      block = owner_arena[call.block.not_nil!].as(Adamas::Compiler::Frontend::BlockNode)
      original_param = block.params.not_nil!.first
      block.params.not_nil![0] = Adamas::Compiler::Frontend::Parameter.new(
        "wrong".to_slice,
        span: original_param.span,
        name_span: original_param.name_span,
      )

      sources = {owner_arena.object_id.to_u64 => source}
      converter = Adamas::HIR::AstToHir.new(owner_arena, sources_by_arena: sources)
      function = converter.__test_lower_array_each_with_stale_param(block, owner_arena)
      text = hir_text(function)
      text.should_not contain("local \"elem\" : 0")
      text.should contain("copy")
    end

    it "recovers dynamic Array#find parameter keys from source" do
      source = "values.find { |variant| variant == 1 }"
      owner_arena, owner_exprs = parse(source)
      call = owner_arena[owner_exprs.first].as(Adamas::Compiler::Frontend::CallNode)
      block = owner_arena[call.block.not_nil!].as(Adamas::Compiler::Frontend::BlockNode)
      original_param = block.params.not_nil!.first
      block.params.not_nil![0] = Adamas::Compiler::Frontend::Parameter.new(
        "wrong".to_slice,
        span: original_param.span,
        name_span: original_param.name_span,
      )

      sources = {owner_arena.object_id.to_u64 => source}
      converter = Adamas::HIR::AstToHir.new(owner_arena, sources_by_arena: sources)
      function = converter.__test_lower_array_find_dynamic_with_stale_param(block, owner_arena)
      text = hir_text(function)
      text.should_not contain("local \"variant\" : Void")
      text.should_not contain("local \"variant\" : 0")
      text.should contain("index_get")
    end

    it "lowers zero-argument Array#index block form as an Int32 search loop" do
      source = "values.index { |variant| variant == 1 }"
      owner_arena, owner_exprs = parse(source)
      call = owner_arena[owner_exprs.first].as(Adamas::Compiler::Frontend::CallNode)
      block = owner_arena[call.block.not_nil!].as(Adamas::Compiler::Frontend::BlockNode)
      original_param = block.params.not_nil!.first
      block.params.not_nil![0] = Adamas::Compiler::Frontend::Parameter.new(
        "wrong".to_slice,
        span: original_param.span,
        name_span: original_param.name_span,
      )

      sources = {owner_arena.object_id.to_u64 => source}
      converter = Adamas::HIR::AstToHir.new(owner_arena, sources_by_arena: sources)
      function = converter.__test_lower_array_index_block_dynamic_with_stale_param(block, owner_arena)
      instructions = function.blocks.flat_map(&.instructions)
      phis = instructions.compact_map { |instruction| instruction.as?(Adamas::HIR::Phi) }
      phis.any? { |phi| phi.type == Adamas::HIR::TypeRef::INT32 }.should be_true
      result_phis = phis.select do |phi|
        converter.__test_get_type_name_from_ref(phi.type) == "Nil | Int32"
      end
      result_phis.should_not be_empty
      result_phis.any? { |phi| phi.incoming_size == 2 }.should be_true
      result_type = converter.__test_type_ref_for_name("Nil | Int32")
      nil_variant = converter.__test_union_variant_id(result_type, Adamas::HIR::TypeRef::NIL)
      int_variant = converter.__test_union_variant_id(result_type, Adamas::HIR::TypeRef::INT32)
      nil_variant.should be >= 0
      int_variant.should be >= 0
      nil_variant.should_not eq(int_variant)
      instructions.compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
        .none? { |call| call.method_name.includes?("#index") }
        .should be_true
    end

    it "dispatches Array#index block form before Indexable expansion" do
      converter = lower_program_with_sources(<<-CRYSTAL)
        def probe(values : Array(Int32)) : Int32?
          values.index { |element| element == 1 }
        end
      CRYSTAL
      function = converter.module.functions.find { |candidate| candidate.name.starts_with?("probe") }
      function.should_not be_nil
      instructions = function.not_nil!.blocks.flat_map(&.instructions)
      phis = instructions.compact_map { |instruction| instruction.as?(Adamas::HIR::Phi) }
      phis.any? { |phi| phi.type == Adamas::HIR::TypeRef::INT32 }.should be_true
      phis.any? do |phi|
        converter.__test_get_type_name_from_ref(phi.type) == "Nil | Int32" && phi.incoming_size == 2
      end.should be_true
      instructions.compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
        .none? { |call| call.method_name.includes?("#index") }
        .should be_true
    end

    it "fails closed when the Array#index result union is missing Int32" do
      converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)

      union_type = converter.__test_type_ref_for_name("Nil | Int32")
      mir_union_type = Adamas::MIR::TypeRef.from_hir(union_type)
      descriptor = converter.union_descriptors[mir_union_type].not_nil!
      poisoned = Adamas::MIR::UnionDescriptor.new(
        descriptor.name,
        descriptor.variants.reject { |variant| variant.full_name == "Int32" },
        descriptor.total_size,
        descriptor.alignment,
      )
      converter.union_descriptors[mir_union_type] = poisoned
      converter.union_descriptor_entries << Adamas::HIR::UnionDescriptorRegistration.new(mir_union_type, poisoned)

      expect_raises(Adamas::HIR::LoweringError, /missing Nil and Int32/) do
        converter.__test_array_index_union_variant_ids("Nil | Int32")
      end
    end

    it "keeps StaticArray#index on the ordinary path instead of dynamic ArraySize" do
      converter = lower_program_with_sources(<<-CRYSTAL)
        def probe(values : StaticArray(Int32, 2)) : Int32?
          values.index { |element| element == 1 }
        end
      CRYSTAL
      function = converter.module.functions.find { |candidate| candidate.name.starts_with?("probe") }
      function.should_not be_nil
      instructions = function.not_nil!.blocks.flat_map(&.instructions)
      instructions.count { |instruction| instruction.is_a?(Adamas::HIR::ArraySize) }.should eq(0)
      instructions.compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
        .any? { |call| call.method_name.includes?("#index") }
        .should be_true
    end

    it "materializes a side-effecting Array#index block receiver exactly once" do
      converter = lower_program_with_sources(<<-CRYSTAL)
        class ProbeReceiver
          def index(&block : Int32 -> Bool) : Int32?
            nil
          end
        end

        def receiver : ProbeReceiver
          ProbeReceiver.new
        end

        def probe : Int32?
          receiver.index { |element| element == 1 }
        end
      CRYSTAL
      function = converter.module.functions.find { |candidate| candidate.name.starts_with?("probe") }
      function.should_not be_nil
      value_calls = function.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end.select { |call| call.method_name.starts_with?("receiver") }
      value_calls.size.should eq(1)
    end
  end

  describe "Array block shorthand receiver binding" do
    it "resolves reject(&.empty?) against each String element" do
      converter = lower_program_with_sources(<<-CRYSTAL)
        def probe(values : Array(String)) : Array(String)
          values.reject(&.empty?)
        end
      CRYSTAL
      function = converter.module.functions.find { |candidate| candidate.name.starts_with?("probe") }
      function.should_not be_nil
      function = function.not_nil!

      calls = function.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end
      empty_calls = calls.select { |call| call.method_name.includes?("empty?") }

      empty_calls.should_not be_empty
      empty_calls.any? { |call| call.method_name.includes?("#empty?") }.should be_true
      empty_calls.any? { |call| !call.has_receiver? }.should be_false
      empty_calls.any? { |call| call.method_name == "empty?" || call.method_name == "empty$Q" }.should be_false
    end
  end

  describe "Array#compact_map block-local next lowering" do
    it "keeps next inside the block and still forms the compacted result" do
      function = lower_function(<<-CRYSTAL)
        def probe(values : Array(Int32)) : Array(Int32)
          values.compact_map do |value|
            next if value < 0
            value
          end
        end
      CRYSTAL

      # A block-local `next` must jump to the compact_map iteration result,
      # not emit a Return from the enclosing method. The method itself still
      # has exactly one Return, carrying the newly allocated result array.
      function.blocks.count { |block| block.terminator.is_a?(Adamas::HIR::Return) }.should eq(1)
      instructions = function.blocks.flat_map(&.instructions)
      instructions.count { |instruction| instruction.is_a?(Adamas::HIR::ArrayNew) }.should eq(1)
      instructions.count { |instruction| instruction.is_a?(Adamas::HIR::ArraySetSize) }.should eq(1)
    end
  end

  describe "synthetic main arena ownership" do
    it "restores the caller arena before later function lowering" do
      owner_source = <<-CRYSTAL
        def arena_owner_probe : Int32
          11
        end
        0
      CRYSTAL
      foreign_source = <<-CRYSTAL
        def arena_owner_probe : Int32
          22
        end
        true
      CRYSTAL
      owner_arena, owner_exprs = parse(owner_source)
      foreign_arena, foreign_exprs = parse(foreign_source)
      converter = Adamas::HIR::AstToHir.new(
        owner_arena,
        main_arenas: [owner_arena, foreign_arena] of Adamas::Compiler::Frontend::ArenaLike,
      )
      converter.no_prelude = true

      owner_def = owner_exprs.compact_map do |expr_id|
        owner_arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode)
      end.first
      foreign_main_expr = foreign_exprs.find do |expr_id|
        !foreign_arena[expr_id].is_a?(Adamas::Compiler::Frontend::DefNode)
      end.not_nil!
      foreign_main_ref = (1_u64 << 32) | foreign_main_expr.index.to_u64
      converter.lower_main([foreign_main_ref])

      function = converter.lower_def(owner_def)
      literals = function.blocks.flat_map(&.instructions)
        .compact_map(&.as?(Adamas::HIR::Literal))
        .map(&.value)

      literals.includes?(11_i64).should be_true
      literals.includes?(22_i64).should be_false
    end
  end

  describe "synthetic stdio puts receiver typing" do
    it "keeps bare puts on the concrete deferred STDOUT type" do
      converter = lower_program_with_main(<<-CRYSTAL)
        abstract class IO
          def puts(string : String)
          end
        end

        class IO::FileDescriptor < IO
        end

        class Unrelated < IO
        end

        puts "ok"
      CRYSTAL

      function = converter.module.function_by_name("__adamas_main")
      function.should_not be_nil
      fd_type = converter.__test_type_ref_for_name("IO::FileDescriptor")
      fd_type.should_not eq(Adamas::HIR::TypeRef::VOID)
      instructions = function.not_nil!.blocks.flat_map(&.instructions)
      puts_calls = instructions.compact_map do |instruction|
        next unless instruction.is_a?(Adamas::HIR::Call)
        next unless instruction.method_name == "IO#puts$String"
        instruction
      end
      puts_calls.should_not be_empty
      puts_call = puts_calls.first
      puts_call.virtual.should be_true
      stdout_get = instructions.find { |instruction| instruction.id == puts_call.receiver_value }
      stdout_get.should be_a(Adamas::HIR::ClassVarGet)
      stdout_get = stdout_get.as(Adamas::HIR::ClassVarGet)
      stdout_get.class_name.should eq("Object")
      stdout_get.var_name.should eq("STDOUT")
      stdout_get.type.should eq(fd_type)

      converter.module.function_by_name("IO::FileDescriptor#puts$String").should_not be_nil
      converter.module.function_by_name("Unrelated#puts$String").should be_nil
    end
  end

  describe "absolute generic paths" do
    it "keeps ::Set(String) rooted at the top level inside nested modules" do
      converter = lower_program(<<-CRYSTAL)
        class Set(T)
          def self.new
            uninitialized self
          end

          def includes?(value : T)
            true
          end
        end

        module Adamas::MIR
          def self.probe
            seen = ::Set(String).new
            seen.includes?("x")
          end
        end
      CRYSTAL

      func = converter.module.functions.find { |f| f.name == "Adamas::MIR.probe$arity0" }
      func.should_not be_nil

      text = hir_text(func.not_nil!)
      text.should contain("call ::Set(String).new()")
      text.should_not contain("__adamas_string_includes_string")

      new_call = func.not_nil!.blocks[0].instructions.find do |inst|
        inst.is_a?(Adamas::HIR::Call) && inst.as(Adamas::HIR::Call).method_name.ends_with?(".new")
      end
      new_call.should_not be_nil
      desc = converter.module.get_type_descriptor(new_call.not_nil!.as(Adamas::HIR::Call).type)
      desc.should_not be_nil
      desc.not_nil!.name.should contain("Set(String)")
    end

    it "keeps ::Set(String) rooted at the top level inside nested classes" do
      converter = lower_program(<<-CRYSTAL)
        class Set(T)
          def self.new
            uninitialized self
          end

          def includes?(value : T)
            true
          end
        end

        module Adamas::MIR
          class HIRToMIRLowering
            def prepare
              seen_names = ::Set(String).new
              seen_names.includes?("x")
            end
          end
        end
      CRYSTAL

      func = converter.module.functions.find { |f| f.name == "Adamas::MIR::HIRToMIRLowering#prepare$arity0" }
      func.should_not be_nil

      text = hir_text(func.not_nil!)
      text.should contain("call ::Set(String).new()")
      text.should_not contain("__adamas_string_includes_string")
    end

    it "does not drift ::Set(String).new receivers into nested Set types" do
      converter = lower_program(<<-CRYSTAL)
        class Set(T)
          def self.new
            uninitialized self
          end

          def includes?(value : T)
            true
          end
        end

        module Adamas::MIR
          class Set(T)
            def self.new
              uninitialized self
            end

            def includes?(value : T)
              false
            end
          end

          class HIRToMIRLowering
            def prepare
              seen_names = ::Set(String).new
              seen_names.includes?("x")
            end
          end
        end
      CRYSTAL

      func = converter.module.functions.find { |f| f.name == "Adamas::MIR::HIRToMIRLowering#prepare$arity0" }
      func.should_not be_nil

      new_call = func.not_nil!.blocks[0].instructions.find do |inst|
        inst.is_a?(Adamas::HIR::Call) && inst.as(Adamas::HIR::Call).method_name.ends_with?(".new")
      end
      new_call.should_not be_nil

      new_desc = converter.module.get_type_descriptor(new_call.not_nil!.as(Adamas::HIR::Call).type)
      new_desc.should_not be_nil
      new_desc.not_nil!.name.should eq("Set(String)")

      includes_call = func.not_nil!.blocks[0].instructions.find do |inst|
        inst.is_a?(Adamas::HIR::Call) && inst.as(Adamas::HIR::Call).method_name.includes?("includes?")
      end
      includes_call.should_not be_nil
      includes_call.not_nil!.as(Adamas::HIR::Call).method_name.should eq("Set(String)#includes?$String")
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POSITIVE TESTS: LITERALS
  # ═══════════════════════════════════════════════════════════════════════════

  describe "literal lowering" do
    it "lowers integer literal" do
      func = lower_function("def foo; 42; end")
      text = hir_text(func)

      text.should contain("literal 42")
      func.blocks.size.should be >= 1
    end

    it "lowers float literal" do
      func = lower_function("def foo; 3.14; end")
      text = hir_text(func)

      text.should contain("literal 3.14")
    end

    it "lowers string literal" do
      func = lower_function("def foo; \"hello\"; end")
      text = hir_text(func)

      text.should contain("literal \"hello\"")
    end

    it "lowers char literal" do
      func = lower_function("def foo; 'a'; end")
      text = hir_text(func)

      text.should contain("literal 97 : Char")
    end

    it "lowers bool literals" do
      func = lower_function("def foo; true; end")
      text = hir_text(func)

      text.should contain("literal true")
    end

    it "lowers nil literal" do
      func = lower_function("def foo; nil; end")
      text = hir_text(func)

      text.should contain("literal nil")
    end

    it "lowers symbol literal" do
      func = lower_function("def foo; :hello; end")
      text = hir_text(func)

      text.should contain("literal")
      text.should contain("Symbol")
    end

    it "lowers negative numbers" do
      func = lower_function("def foo; -42; end")
      text = hir_text(func)

      # Should have unary negation
      text.should contain("unop Neg")
    end

    it "lowers typed integer suffixes" do
      func = lower_function("def foo; 42_i64; end")
      text = hir_text(func)

      # Should have Int64 type
      func.blocks[0].instructions.first.type.should eq(Adamas::HIR::TypeRef::INT64)
    end
  end

  describe "enum symbol arguments" do
    it "casts symbol literal to enum value and mangles double splat calls" do
      code = <<-CR
        enum Section
          Sched
        end

        def trace(section : Section, **metadata)
        end

        trace :sched, foo: 1
      CR

      converter = lower_program_with_main(code)
      text = converter.module.to_s

      # Symbol :sched is converted to enum value 0
      text.should contain("literal 0 : Int32")
      # Double splat methods use _double_splat suffix in mangled name
      text.should contain("call trace$Section_NamedTuple_double_splat")
    end

    it "resolves module-qualified enum types in context" do
      code = <<-CR
        module Crystal
          module Tracing
            enum Section
              Sched
            end
          end

          def self.trace(section : Tracing::Section, **metadata)
          end
        end

        Crystal.trace :sched, foo: 1
      CR

      converter = lower_program_with_main(code)
      text = converter.module.to_s

      text.should contain("call Crystal.trace$Crystal::Tracing::Section_NamedTuple_double_splat")
    end

    it "inlines a yield-only Crystal.trace overload with named metadata" do
      code = <<-CR
        module Crystal
          module Tracing
            alias Section = Symbol
          end

          def self.trace(section : Tracing::Section, operation : String, time : UInt64? = nil, **metadata, &)
            yield
          end

          def self.trace(section : Tracing::Section, operation : String, time : UInt64? = nil, **metadata) : Nil
          end
        end

        module Probe
          def self.allocate(size : Int32) : Int32
            Crystal.trace(:gc, "malloc_atomic", size: size) do
              size.to_i32
            end
          end
        end

        Probe.allocate(4)
      CR

      converter = lower_program_with_main(code)
      main = converter.module.function_by_name("__adamas_main")
      main.should_not be_nil
      puts converter.module.functions.map(&.name).join("\n")
      text = hir_text(main.not_nil!)
      text.should_not contain("call Crystal.trace")
      text.should_not contain("with_block")

      probe = converter.module.functions.find { |func| func.name.starts_with?("Probe.allocate") }
      probe.should_not be_nil
      probe_text = hir_text(probe.not_nil!)
      probe_text.should contain("copy")
      probe_text.should_not contain("call Crystal.trace")
      probe_text.should_not contain("with_block")
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POSITIVE TESTS: VARIABLES
  # ═══════════════════════════════════════════════════════════════════════════

  describe "variable lowering" do
    it "lowers local variable assignment" do
      func = lower_function("def foo; x = 1; end")
      text = hir_text(func)

      text.should contain("local")
      text.should contain("x")
    end

    it "lowers local variable reference" do
      func = lower_function("def foo; x = 1; x; end")
      text = hir_text(func)

      text.should contain("copy")
    end

    it "lowers instance variable read" do
      func = lower_function("def foo; @value; end")
      text = hir_text(func)

      text.should contain("field_get")
      text.should contain("@value")
    end

    it "lowers instance variable write" do
      func = lower_function("def foo; @value = 42; end")
      text = hir_text(func)

      text.should contain("field_set")
      text.should contain("@value")
    end

    it "refines an untyped ivar shortcut from a later typed getter" do
      source = <<-CRYSTAL
        class DeferredIvarType
          def initialize(@path)
          end

          getter path : String
        end
      CRYSTAL
      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena
      class_node = exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
      end.first
      converter.register_class(class_node)

      path_ivar = converter.class_info["DeferredIvarType"].ivars.find do |ivar|
        ivar.name == "@path"
      end
      path_ivar.should_not be_nil
      path_ivar.not_nil!.type.should eq(Adamas::HIR::TypeRef::STRING)
    end

    it "invalidates a cached nil local inference after a dependency is typed" do
      arena, roots = parse("x = y")
      converter = Adamas::HIR::AstToHir.new(arena)

      before, after = converter.__test_local_inference_after_dependency_update(
        roots,
        "x",
        "y",
      )
      before.should be_nil
      after.should eq("Int32")
    end

    it "prefers a body-local dependency over a stale ambient local type" do
      arena, roots = parse("dependency = 1_i64\nx = dependency")
      converter = Adamas::HIR::AstToHir.new(arena)

      before, after = converter.__test_local_inference_after_dependency_update(
        roots,
        "x",
        "dependency",
      )
      before.should eq("Int64")
      after.should eq("Int64")
    end

    it "fails closed for a cyclic body-local dependency with a stale ambient type" do
      arena, roots = parse("dependency = x\nx = dependency")
      converter = Adamas::HIR::AstToHir.new(arena)

      before, after = converter.__test_local_inference_after_dependency_update(
        roots,
        "x",
        "dependency",
      )
      before.should be_nil
      after.should be_nil
    end

    it "restores the optional self context around expression inference" do
      arena, roots = parse("self\nself\nself")
      converter = Adamas::HIR::AstToHir.new(arena)

      converter.__test_infer_type_name(roots[0], "InferenceContext").should eq("InferenceContext")
      converter.__test_infer_self_type_name.should be_nil
      converter.__test_infer_type_name(roots[1], nil).should be_nil
      converter.__test_infer_self_type_name.should be_nil
      converter.__test_infer_type_name(roots[2], "InferenceContext").should eq("InferenceContext")
      converter.__test_infer_self_type_name.should be_nil
    end

    it "keeps cached expression inference scoped to the self context" do
      arena, roots = parse("self")
      converter = Adamas::HIR::AstToHir.new(arena)

      converter.__test_infer_type_name(roots[0], nil).should be_nil
      converter.__test_infer_type_name(roots[0], "InferenceContext").should eq("InferenceContext")
      converter.__test_infer_type_name(roots[0], nil).should be_nil
    end

    it "lowers class variable read" do
      func = lower_function("def foo; @@count; end")
      text = hir_text(func)

      text.should contain("classvar_get")
      text.should contain("@@count")
    end

    it "lowers class variable write" do
      func = lower_function("def foo; @@count = 0; end")
      text = hir_text(func)

      text.should contain("classvar_set")
    end

    it "lowers self" do
      func = lower_function("def foo; self; end")
      text = hir_text(func)

      text.should contain("local \"self\"")
    end

    it "lowers function parameters" do
      func = lower_function("def foo(x, y); x; end")

      func.params.size.should eq(2)
      func.params[0].name.should eq("x")
      func.params[1].name.should eq("y")
    end

    it "lowers typed parameters" do
      func = lower_function("def foo(x : Int32); x; end")

      func.params[0].type.should eq(Adamas::HIR::TypeRef::INT32)
    end
  end

  describe "block type lowering" do
    it "captures block parameter types as Proc" do
      func, converter = lower_function_with_converter("def foo(&block : Int32 -> String); 1; end")
      param = func.params.find { |p| p.name == "block" }
      param.should_not be_nil
      desc = converter.module.get_type_descriptor(param.not_nil!.type)
      desc.should_not be_nil
      desc.not_nil!.kind.should eq(Adamas::HIR::TypeKind::Proc)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POSITIVE TESTS: BINARY OPERATIONS
  # ═══════════════════════════════════════════════════════════════════════════

  describe "binary operation lowering" do
    it "lowers arithmetic operations" do
      func = lower_function("def foo; 1 + 2; end")
      text = hir_text(func)

      text.should contain("binop Add")
    end

    it "lowers subtraction" do
      func = lower_function("def foo; 5 - 3; end")
      text = hir_text(func)

      text.should contain("binop Sub")
    end

    it "lowers multiplication" do
      func = lower_function("def foo; 2 * 3; end")
      text = hir_text(func)

      text.should contain("binop Mul")
    end

    it "lowers division" do
      func = lower_function("def foo; 10 / 2; end")
      text = hir_text(func)

      text.should contain("binop Div")
    end

    it "lowers modulo" do
      func = lower_function("def foo; 10 % 3; end")
      text = hir_text(func)

      text.should contain("binop Mod")
    end

    it "lowers comparison operations" do
      func = lower_function("def foo; 1 < 2; end")
      text = hir_text(func)

      text.should contain("binop Lt")
    end

    it "lowers equality" do
      func = lower_function("def foo; 1 == 1; end")
      text = hir_text(func)

      text.should contain("binop Eq")
    end

    it "lowers logical and" do
      func = lower_function("def foo(x : Bool, y : Bool); x && y; end")
      text = hir_text(func)

      text.should contain("branch")
      text.should contain("phi")
    end

    it "lowers logical or" do
      func = lower_function("def foo(x : Bool, y : Bool); x || y; end")
      text = hir_text(func)

      text.should contain("branch")
      text.should contain("phi")
    end

    it "lowers bitwise operations" do
      func = lower_function("def foo; 1 & 2; end")
      text = hir_text(func)

      text.should contain("binop BitAnd")
    end

    it "lowers shift operations" do
      func = lower_function("def foo; 1 << 2; end")
      text = hir_text(func)

      text.should contain("binop Shl")
    end

    it "lowers chained operations" do
      func = lower_function("def foo; 1 + 2 + 3; end")
      text = hir_text(func)

      # Should have two Add operations
      text.scan(/binop Add/).size.should eq(2)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POSITIVE TESTS: UNARY OPERATIONS
  # ═══════════════════════════════════════════════════════════════════════════

  describe "unary operation lowering" do
    it "lowers negation" do
      func = lower_function("def foo; -x; end")
      text = hir_text(func)

      text.should contain("unop Neg")
    end

    it "lowers logical not" do
      func = lower_function("def foo; !true; end")
      text = hir_text(func)

      text.should contain("unop Not")
    end

    it "lowers bitwise not" do
      func = lower_function("def foo; ~1; end")
      text = hir_text(func)

      text.should contain("unop BitNot")
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POSITIVE TESTS: CONTROL FLOW
  # ═══════════════════════════════════════════════════════════════════════════

  describe "control flow lowering" do
    it "lowers if expression" do
      # Use a non-constant condition so the lowering must build a real CFG.
      func = lower_function("def foo(x : Bool); if x; 1; end; end")
      text = hir_text(func)

      text.should contain("branch")
      text.should contain("phi")
      func.blocks.size.should be >= 3  # entry, then, else, merge
    end

    it "lowers if-else expression" do
      func = lower_function("def foo(x : Bool); if x; 1; else; 2; end; end")
      text = hir_text(func)

      text.should contain("branch")
      text.should contain("phi")
    end

    it "lowers unless expression" do
      func = lower_function("def foo(x : Bool); unless x; 1; end; end")
      text = hir_text(func)

      text.should contain("unop Not")  # Condition negated
      text.should contain("branch")
    end

    it "lowers while loop" do
      func = lower_function("def foo(x : Bool); while x; 1; end; end")
      text = hir_text(func)

      text.should contain("branch")
      text.should contain("jump")
    end

    it "lowers until loop" do
      func = lower_function("def foo(x : Bool); until x; 1; end; end")
      text = hir_text(func)

      text.should contain("branch")
      text.should contain("jump")
    end

    it "lowers ternary expression" do
      func = lower_function("def foo(x : Bool); x ? 1 : 2; end")
      text = hir_text(func)

      text.should contain("branch")
      text.should contain("phi")
    end

    it "lowers case expression" do
      func = lower_function("def foo(x); case x; when 1; \"one\"; when 2; \"two\"; else; \"other\"; end; end")
      text = hir_text(func)

      text.should contain("binop Eq")
      text.should contain("phi")
    end

    it "keeps an unbound case subject as a receiverless method call" do
      converter = lower_program(<<-CRYSTAL)
        class Cursor
          def current_byte : Int32
            48
          end

          def advance : Nil
          end

          def parse : Int32
            initial = current_byte
            case current_byte
            when 48
              advance
              current_byte
            else
              -1
            end
          end
        end
        CRYSTAL
      func = converter.module.functions.find { |candidate| candidate.name.starts_with?("Cursor#parse") }.not_nil!

      current_byte_calls = func.blocks.flat_map(&.instructions).compact_map do |instruction|
        call = instruction.as?(Adamas::HIR::Call)
        call if call && call.method_name.includes?("current_byte")
      end

      current_byte_calls.size.should eq(3)
      hir_text(func).should_not contain("local current_byte")
    end

    it "still narrows a bound local used as a case subject" do
      converter = lower_program(<<-CRYSTAL)
        class Cursor
          def current_byte : Int32
            48
          end

          def parse : Int32
            byte = current_byte
            case byte
            when 48
              byte
            else
              -1
            end
          end
        end
        CRYSTAL
      func = converter.module.functions.find { |candidate| candidate.name.starts_with?("Cursor#parse") }.not_nil!

      current_byte_calls = func.blocks.flat_map(&.instructions).compact_map do |instruction|
        call = instruction.as?(Adamas::HIR::Call)
        call if call && call.method_name.includes?("current_byte")
      end

      current_byte_calls.size.should eq(1)
      hir_text(func).should contain("local \"byte\"")
    end

    it "keeps a case type refinement on a member-access receiver" do
      converter = lower_program(<<-CRYSTAL)
        struct CaseExprId
          getter index : Int32

          def initialize(@index : Int32)
          end
        end

        abstract class CaseNodeBase
        end

        class CaseAssignNode < CaseNodeBase
          getter value : CaseExprId

          def initialize(@value : CaseExprId)
          end
        end

        class CaseOtherNode < CaseNodeBase
        end

        class CaseProbe
          def consume(expr_id : CaseExprId) : Int32
            expr_id.index
          end

          def inspect_node(node : CaseNodeBase?) : Int32?
            case node
            when CaseAssignNode
              consume(node.value)
            else
              nil
            end
          end

          def inspect_either(node : CaseNodeBase?) : CaseNodeBase?
            case node
            when CaseAssignNode, CaseOtherNode
              node
            else
              nil
            end
          end
        end
        CRYSTAL
      func = converter.module.functions.find { |candidate| candidate.name.starts_with?("CaseProbe#inspect_node") }.not_nil!
      calls = func.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))

      calls.any? { |call| call.method_name.starts_with?("CaseAssignNode#value") }.should be_true
      calls.any? { |call| call.method_name.starts_with?("Nil | CaseNodeBase#value") }.should be_false
      calls.any? { |call| call.method_name.starts_with?("CaseProbe#consume$CaseExprId") }.should be_true
      hir_text(func).should contain("union_unwrap")
      hir_text(func).should contain("is_a")

      either = converter.module.functions.find { |candidate| candidate.name.starts_with?("CaseProbe#inspect_either") }.not_nil!
      hir_text(either).should_not contain("cast")
    end

    it "narrows multi-type case branches before resolving optional-parameter calls" do
      converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
        abstract class CaseMultiBase
        end

        class CaseMultiFirst < CaseMultiBase
        end

        class CaseMultiSecond < CaseMultiBase
        end

        class CaseMultiThird < CaseMultiBase
        end

        class CaseMultiProbe
          def source : CaseMultiBase
            CaseMultiFirst.new
          end

          def accept(
            member : CaseMultiFirst | CaseMultiSecond | CaseMultiThird,
            owner : String,
            values : Array(Int32)?,
            offset : Pointer(Int32)?,
          ) : Nil
          end

          def accept_first(
            member : CaseMultiFirst,
            owner : String,
            values : Array(Int32)?,
            offset : Pointer(Int32)?,
          ) : Nil
          end

          def inspect(owner : String, values : Array(Int32), offset : Pointer(Int32)) : Nil
            member = source
            case member
            when CaseMultiFirst, CaseMultiSecond, CaseMultiThird
              accept(member, owner, values, offset)
            end
            case member
            when CaseMultiFirst, CaseMultiFirst
              accept_first(member, owner, values, offset)
            end
          end

          def inspect_concrete(
            member : CaseMultiFirst,
            owner : String,
            values : Array(Int32),
            offset : Pointer(Int32),
          ) : Nil
            case member
            when CaseMultiFirst, CaseMultiSecond
              accept_first(member, owner, values, offset)
            end
          end
        end

        offset = 0
        CaseMultiProbe.new.inspect("owner", Array(Int32).new, pointerof(offset))
        CaseMultiProbe.new.inspect_concrete(CaseMultiFirst.new, "owner", Array(Int32).new, pointerof(offset))
        CRYSTAL
      func = converter.module.functions.find { |candidate| candidate.name.starts_with?("CaseMultiProbe#inspect") }.not_nil!
      calls = func.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
      accept_calls = calls.select { |call| call.method_name.starts_with?("CaseMultiProbe#accept$") }

      accept_calls.map(&.method_name).should eq([
        "CaseMultiProbe#accept$CaseMultiFirst | CaseMultiSecond | CaseMultiThird_String_Array(Int32)_Pointer(Int32)",
      ])
      accept_first_calls = calls.select { |call| call.method_name.starts_with?("CaseMultiProbe#accept_first$") }
      accept_first_calls.map(&.method_name).should eq([
        "CaseMultiProbe#accept_first$CaseMultiFirst_String_Array(Int32)_Pointer(Int32)",
      ])
      concrete_func = converter.module.functions.find { |candidate| candidate.name.starts_with?("CaseMultiProbe#inspect_concrete$") }.not_nil!
      concrete_calls = concrete_func.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
      concrete_calls.select { |call| call.method_name.starts_with?("CaseMultiProbe#accept_first$") }.map(&.method_name).should eq([
        "CaseMultiProbe#accept_first$CaseMultiFirst_String_Array(Int32)_Pointer(Int32)",
      ])
    end

    it "fails closed when overlapping union carriers cannot prove branch narrowing" do
      expect_raises(Adamas::HIR::LoweringError, /ambiguous descendant carriers for AmbiguousChild in union Nil \| AmbiguousBase \| AmbiguousMid/) do
        lower_program(<<-CRYSTAL)
          struct AmbiguousExprId
            getter index : Int32

            def initialize(@index : Int32)
            end
          end

          abstract class AmbiguousBase
          end

          class AmbiguousMid < AmbiguousBase
          end

          class AmbiguousChild < AmbiguousMid
            getter value : AmbiguousExprId

            def initialize(@value : AmbiguousExprId)
            end
          end

          class AmbiguousProbe
            def inspect_node(node : AmbiguousBase | AmbiguousMid | Nil) : Int32?
              case node
              when AmbiguousChild
                node.value.index
              else
                nil
              end
            end
          end
          CRYSTAL
      end
    end

    it "distinguishes a cached method result from a local initialized by another call" do
      arena = Adamas::Compiler::Frontend::AstArena.new
      converter = Adamas::HIR::AstToHir.new(arena)
      function = converter.module.create_function("__test_case_subject_provenance", Adamas::HIR::TypeRef::NIL)
      ctx = Adamas::HIR::LoweringContext.new(function, converter.module, arena)

      receiver = Adamas::HIR::Literal.new(ctx.next_id, Adamas::HIR::TypeRef::POINTER, nil)
      ctx.emit(receiver)

      current_byte = Adamas::HIR::Call.with_receiver(
        ctx.next_id,
        Adamas::HIR::TypeRef::INT32,
        receiver.id,
        "Cursor#current_byte",
        [] of Adamas::HIR::ValueId,
      )
      ctx.emit(current_byte)
      cached_read = Adamas::HIR::Copy.new(ctx.next_id, Adamas::HIR::TypeRef::INT32, current_byte.id)
      ctx.emit(cached_read)

      arena_read = Adamas::HIR::Call.with_receiver(
        ctx.next_id,
        Adamas::HIR::TypeRef::POINTER,
        receiver.id,
        "AstArena#[]$ExprId",
        [] of Adamas::HIR::ValueId,
      )
      ctx.emit(arena_read)
      local_value = Adamas::HIR::Copy.new(ctx.next_id, Adamas::HIR::TypeRef::POINTER, arena_read.id)
      ctx.emit(local_value)

      converter.__test_case_subject_cached_method_result?(ctx, cached_read.id, "current_byte").should be_true
      converter.__test_case_subject_cached_method_result?(ctx, local_value.id, "node").should be_false
    end

    it "lowers nested if" do
      func = lower_function("def foo(a : Bool, b : Bool); if a; if b; 1; end; end; end")
      text = hir_text(func)

      # Multiple branches
      text.scan(/branch/).size.should be >= 2
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POSITIVE TESTS: FUNCTIONS
  # ═══════════════════════════════════════════════════════════════════════════

  describe "function lowering" do
    it "lowers return statement" do
      func = lower_function("def foo; return 42; end")
      text = hir_text(func)

      text.should contain("return")
    end

    it "lowers implicit return" do
      func = lower_function("def foo; 42; end")
      text = hir_text(func)

      text.should contain("return")
    end

    it "lowers early return" do
      func = lower_function("def foo; return 1; 2; end")
      text = hir_text(func)

      text.should contain("return")
    end

    it "lowers yield" do
      func = lower_function("def foo; yield 1; end")
      text = hir_text(func)

      text.should contain("yield")
    end

    it "lowers yield with multiple args" do
      func = lower_function("def foo; yield 1, 2, 3; end")
      text = hir_text(func)

      text.should contain("yield")
    end

    it "lowers function with return type" do
      func = lower_function("def foo : Int32; 42; end")

      func.return_type.should eq(Adamas::HIR::TypeRef::INT32)
    end

    it "preserves the final def-body value across an arena switch" do
      func = lower_function("def foo : Int32; 42; end")
      text = hir_text(func)

      text.should contain("literal 42")
      text.should_not contain("literal nil : Nil")
    end

    it "lowers function with multiple parameters" do
      func = lower_function("def foo(a : Int32, b : String, c); end")

      func.params.size.should eq(3)
      func.params[0].type.should eq(Adamas::HIR::TypeRef::INT32)
      func.params[1].type.should eq(Adamas::HIR::TypeRef::STRING)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POSITIVE TESTS: CALLS
  # ═══════════════════════════════════════════════════════════════════════════

  describe "call lowering" do
    it "lowers method call on receiver" do
      func = lower_function("def foo; x.bar; end")
      text = hir_text(func)

      text.should contain("call")
      text.should contain("bar")
    end

    it "resolves enum value method calls" do
      code = <<-CRYSTAL
        enum Signal
          CHLD

          def reset : Int32
            1
          end
        end

        def foo
          Signal::CHLD.reset
        end
      CRYSTAL

      converter = lower_program(code)
      func = converter.module.functions.find { |f| f.name.split("$").first == "foo" }
      func.should_not be_nil

      call = func.not_nil!.blocks.flat_map(&.instructions)
        .find { |inst| inst.is_a?(Adamas::HIR::Call) }
      call.should_not be_nil
      call.not_nil!.as(Adamas::HIR::Call).method_name.should eq("Signal#reset")
    end

    it "drops enum identity across integer conversion calls" do
      converter = lower_program(<<-CRYSTAL)
        enum ConvertedSignal
          Ready
        end

        class ConvertedSignalSink
          def add(value : ConvertedSignal)
          end

          def add(value : Int32)
          end
        end

        def converted_signal_to_integer(
          sink : ConvertedSignalSink,
          signal : ConvertedSignal,
        )
          sink.add(signal.to_i)
        end
      CRYSTAL

      function = converter.module.functions.find do |candidate|
        candidate.name.starts_with?("converted_signal_to_integer$")
      end
      function.should_not be_nil
      add_call = function.not_nil!.blocks.flat_map(&.instructions)
        .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
        .find { |call| call.method_name.starts_with?("ConvertedSignalSink#add") }
      add_call.should_not be_nil
      add_call.not_nil!.method_name.should eq(
        "ConvertedSignalSink#add$Int32",
      )
    end

    it "does not treat a known nominal type as a same-suffix enum" do
      converter = lower_program(<<-CRYSTAL)
        module EnumSuffixOwner
          enum Options
            Enabled
          end
        end

        module ValueSuffixOwner
          struct Options
          end
        end

        class SuffixIdentitySink
          def add(value : EnumSuffixOwner::Options)
          end

          def add(value : ValueSuffixOwner::Options)
          end
        end

        def preserve_suffix_identity(
          sink : SuffixIdentitySink,
          value : ValueSuffixOwner::Options,
        )
          sink.add(value)
        end
      CRYSTAL

      function = converter.module.functions.find do |candidate|
        candidate.name.starts_with?("preserve_suffix_identity$")
      end
      function.should_not be_nil
      add_call = function.not_nil!.blocks.flat_map(&.instructions)
        .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
        .find { |call| call.method_name.starts_with?("SuffixIdentitySink#add") }
      add_call.should_not be_nil
      add_call.not_nil!.method_name.should eq(
        "SuffixIdentitySink#add$ValueSuffixOwner::Options",
      )
    end

    it "does not propagate enum identity from an unrelated mixed-union arm" do
      converter = lower_program(<<-CRYSTAL)
        enum MixedUnionSignal
          Ready

          def to_s : String
            "signal"
          end
        end

        def mixed_union_string_to_s(value : MixedUnionSignal | String) : String
          value.as(String).to_s
        end
      CRYSTAL

      function = converter.module.functions.find do |candidate|
        candidate.name.starts_with?("mixed_union_string_to_s$")
      end
      function.should_not be_nil
      calls = function.not_nil!.blocks.flat_map(&.instructions)
        .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      calls.none? do |call|
        call.method_name.starts_with?("MixedUnionSignal#to_s")
      end.should be_true
    end

    it "does not propagate enum identity into a raw carrier union arm" do
      converter = lower_program(<<-CRYSTAL)
        struct Int32
          def mixed_union_marker : Int32
            1
          end
        end

        enum CarrierUnionSignal
          Ready

          def mixed_union_marker : Int32
            2
          end
        end

        def carrier_union_marker(signal : CarrierUnionSignal) : Int32
          value : CarrierUnionSignal | Int32 = signal
          value.as(Int32).mixed_union_marker
        end
      CRYSTAL

      function = converter.module.functions.find do |candidate|
        candidate.name.starts_with?("carrier_union_marker$")
      end
      function.should_not be_nil
      marker_call = function.not_nil!.blocks.flat_map(&.instructions)
        .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
        .find { |call| call.method_name.includes?("mixed_union_marker") }
      marker_call.should_not be_nil
      marker_call.not_nil!.method_name.should eq("Int32#mixed_union_marker")
    end

    it "preserves enum call argument identity through conditional local phis" do
      converter = lower_program_with_main(<<-CRYSTAL)
        module EnumPhiProbe
          class Value
            property strategy : Strategy?

            def initialize(@strategy : Strategy? = nil)
            end
          end

          enum Strategy
            Stack
            GC
          end

          class Result
            def add(id : UInt32, strategy : Strategy)
            end
          end

          class Assigner
            def choose(value : Value) : Strategy
              Strategy::Stack
            end

            def assign(result : Result, value : Value, force : Bool)
              strategy = if explicit = value.strategy
                           explicit == Strategy::Stack ? choose(value) : explicit
                         else
                           choose(value)
                         end
              strategy = Strategy::GC if force
              result.add(1_u32, strategy)
            end
          end
        end

        EnumPhiProbe::Assigner.new.assign(
          EnumPhiProbe::Result.new,
          EnumPhiProbe::Value.new,
          false,
        )
      CRYSTAL

      assign_name =
        "EnumPhiProbe::Assigner#assign$EnumPhiProbe::Result_EnumPhiProbe::Value_Bool"
      converter.__test_lower_function_if_needed(assign_name)
      assign = converter.module.function_by_name(assign_name)
      assign.should_not be_nil

      add_call = assign.not_nil!.blocks
        .flat_map(&.instructions)
        .select(Adamas::HIR::Call)
        .find { |call| call.method_name.starts_with?("EnumPhiProbe::Result#add") }
      add_call.should_not be_nil
      add_call.not_nil!.method_name.should eq(
        "EnumPhiProbe::Result#add$UInt32_EnumPhiProbe::Strategy",
      )
    end

    it "recovers forward enum identity from inline getter provenance" do
      arena, exprs = parse(<<-CRYSTAL)
        module Adamas
          module HIR
            class EnumPhiValue
              property strategy : EnumPhiStrategy?
            end

            enum EnumPhiStrategy
              Stack
              GC
            end

            class EnumPhiResult
              def add(id : UInt32, strategy : EnumPhiStrategy)
              end
            end

            class EnumPhiAssigner
              def choose(value : EnumPhiValue) : EnumPhiStrategy
                EnumPhiStrategy::Stack
              end

              def assign(
                result : EnumPhiResult,
                value : EnumPhiValue,
                force : Bool,
              )
                strategy = if explicit = value.strategy
                             explicit == EnumPhiStrategy::Stack ? choose(value) : explicit
                           else
                             choose(value)
                           end
                strategy = EnumPhiStrategy::GC if force
                result.add(1_u32, strategy)
              end
            end
          end
        end
      CRYSTAL

      converter = Adamas::HIR::AstToHir.new(arena)
      converter.arena = arena
      module_expr = exprs.find do |expr_id|
        arena[expr_id].is_a?(Adamas::Compiler::Frontend::ModuleNode)
      end
      module_expr.should_not be_nil
      converter.register_module(
        arena[module_expr.not_nil!].as(Adamas::Compiler::Frontend::ModuleNode),
      )

      getter_name = "Adamas::HIR::EnumPhiValue#strategy"
      converter.__test_enum_return_name_for(getter_name).should eq(
        "Adamas::HIR::EnumPhiStrategy",
      )
      converter.__test_enum_metadata_target_compatible(
        "Int32 | Nil",
        "Adamas::HIR::EnumPhiStrategy",
      ).should be_true
      converter.__test_enum_metadata_target_compatible(
        "String | Nil",
        "Adamas::HIR::EnumPhiStrategy",
      ).should be_false
      converter.__test_enum_metadata_target_compatible(
        "Int32",
        "Adamas::HIR::EnumPhiStrategy",
      ).should be_false
      converter.__test_enum_metadata_target_compatible(
        "Void",
        "Adamas::HIR::EnumPhiStrategy",
      ).should be_false
      converter.__test_enum_metadata_target_compatible(
        "Int32 | Nil",
        "Adamas::HIR::MissingEnum",
      ).should be_false
      converter.__test_force_ivar_type(
        "Adamas::HIR::EnumPhiValue",
        "@strategy",
        "Int32 | Nil",
      )

      assign_name =
        "Adamas::HIR::EnumPhiAssigner#assign$Adamas::HIR::EnumPhiResult_Adamas::HIR::EnumPhiValue_Bool"
      converter.__test_lower_function_if_needed(assign_name)
      assign = converter.module.function_by_name(assign_name)
      assign.should_not be_nil

      add_call = assign.not_nil!.blocks
        .flat_map(&.instructions)
        .select(Adamas::HIR::Call)
        .find { |call| call.method_name.starts_with?("Adamas::HIR::EnumPhiResult#add") }
      add_call.should_not be_nil
      add_call.not_nil!.method_name.should eq(
        "Adamas::HIR::EnumPhiResult#add$UInt32_Adamas::HIR::EnumPhiStrategy",
      )
    end

    it "preserves enum identity through nullable union wraps in nested each blocks" do
      arena, exprs = parse(<<-CRYSTAL)
        module Adamas
          module HIR
            enum NestedUnionStrategy
              Stack
              GC
              Unknown
            end

            class NestedUnionValue
              property strategy : NestedUnionStrategy? = nil
              getter id : UInt32

              def initialize(@id : UInt32)
              end
            end

            class NestedUnionResult
              def add(id : UInt32, strategy : NestedUnionStrategy)
              end
            end

            class NestedUnionAssigner
              getter result : NestedUnionResult

              def initialize
                @result = NestedUnionResult.new
              end

              def assign(values : Array(NestedUnionValue))
                values.each do |value|
                  strategy = if explicit = value.strategy
                               explicit == NestedUnionStrategy::Unknown ? NestedUnionStrategy::Stack : explicit
                             else
                               NestedUnionStrategy::GC
                             end
                  @result.add(value.id, strategy)
                end
              end
            end
          end
        end
      CRYSTAL

      converter = Adamas::HIR::AstToHir.new(arena)
      converter.arena = arena
      module_expr = exprs.find do |expr_id|
        arena[expr_id].is_a?(Adamas::Compiler::Frontend::ModuleNode)
      end
      module_expr.should_not be_nil
      converter.register_module(
        arena[module_expr.not_nil!].as(Adamas::Compiler::Frontend::ModuleNode),
      )

      assign_name =
        "Adamas::HIR::NestedUnionAssigner#assign$Array(Adamas::HIR::NestedUnionValue)"
      converter.__test_lower_function_if_needed(assign_name)
      assign = converter.module.function_by_name(assign_name)
      assign.should_not be_nil

      add_calls = assign.not_nil!.blocks
        .flat_map(&.instructions)
        .select(Adamas::HIR::Call)
        .select { |call| call.method_name.starts_with?("Adamas::HIR::NestedUnionResult#add") }
      add_calls.size.should eq(1)
      add_calls.first.method_name.should eq(
        "Adamas::HIR::NestedUnionResult#add$UInt32_Adamas::HIR::NestedUnionStrategy",
      )
    end

    it "applies default args for member access calls" do
      code = <<-CRYSTAL
        class Foo
          def bar(x : Int32 = 1, y : Int32 = 2) : Int32
            x + y
          end
        end

        def foo
          Foo.new.bar
        end
      CRYSTAL

      converter = lower_program(code)
      func = converter.module.functions.find { |f| f.name.split("$").first == "foo" }
      func.should_not be_nil

      call = func.not_nil!.blocks.flat_map(&.instructions)
        .find { |inst| inst.is_a?(Adamas::HIR::Call) && inst.as(Adamas::HIR::Call).method_name.includes?("Foo#bar") }
      call.should_not be_nil
      call.not_nil!.as(Adamas::HIR::Call).args.size.should eq(2)
    end

    it "does not rematerialize expanded defaults as concrete allocator shapes" do
      converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
        class CanonicalDefaultInitializer
          def initialize(
            @value : Int32,
            @label : String = "default",
            @optional : Int32? = nil,
          )
            @marker = 7
          end
        end

        CanonicalDefaultInitializer.new(1)
      CRYSTAL

      converter.__test_process_pending_lower_functions
      initializers = converter.module.functions.select do |function|
        function.name.starts_with?("CanonicalDefaultInitializer#initialize$") &&
          !function.blocks.empty?
      end
      canonical_name = "CanonicalDefaultInitializer#initialize$Int32_String_Nil | Int32"

      initializers.map(&.name).should eq([canonical_name])
      initializers.first.params.size.should eq(4)
      converter.__test_get_type_name_from_ref(initializers.first.params[3].type).should eq("Nil | Int32")

      main_allocator_calls = converter.module.function_by_name("__adamas_main").not_nil!
        .blocks
        .flat_map(&.instructions)
        .compact_map(&.as?(Adamas::HIR::Call))
        .select { |call| call.method_name.starts_with?("CanonicalDefaultInitializer.new$") }
      main_allocator_calls.map(&.method_name).should eq(["CanonicalDefaultInitializer.new$Int32"])

      allocator_calls = converter.module.functions
        .select { |function| function.name.starts_with?("CanonicalDefaultInitializer.new$") }
        .flat_map(&.blocks)
        .flat_map(&.instructions)
        .compact_map(&.as?(Adamas::HIR::Call))
        .select { |call| call.method_name.starts_with?("CanonicalDefaultInitializer#initialize$") }
      allocator_calls.should_not be_empty
      allocator_calls.map(&.method_name).uniq.should eq([canonical_name])
    end

    it "binds default params before inline yield lowering" do
      code = <<-CRYSTAL
        def each_with_index_like(offset = 0)
          while offset < 3
            yield offset
            offset += 1
          end
        end

        def probe
          each_with_index_like do |i|
            i + 10
          end
        end
      CRYSTAL

      converter = lower_program(code)
      func = converter.module.functions.find { |f| f.name.split("$").first == "probe" }
      func.should_not be_nil

      text = hir_text(func.not_nil!)
      text.should contain("literal 0 : Int32")
      text.should_not contain("local \"offset\" : 0")
    end

    it "consumes a packed splat slot before trailing named defaults" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class BacktraceSink
        end

        class ErrorProbe
          def inspect_with_backtrace(io : BacktraceSink) : Nil
          end
        end

        module BufferedProbe
          def self.message(message : String, *args, exception = nil, backtrace = nil)
            exception.inspect_with_backtrace(backtrace) if exception
          end
        end

        BufferedProbe.message(
          "message",
          "arg",
          exception: ErrorProbe.new,
          backtrace: BacktraceSink.new,
        )
      CRYSTAL

      message = converter.module.functions.find do |func|
        func.name.starts_with?("BufferedProbe.message$String_Tuple(String)_ErrorProbe_BacktraceSink")
      end
      message.should_not be_nil
      message.not_nil!.params.map { |param| converter.__test_get_type_name_from_ref(param.type) }.should eq([
        "String",
        "Tuple(String)",
        "ErrorProbe",
        "BacktraceSink",
      ])

      call = message.not_nil!.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call)).find do |candidate|
        candidate.method_name.includes?("inspect_with_backtrace")
      end
      call.should_not be_nil
      call.not_nil!.method_name.should eq("ErrorProbe#inspect_with_backtrace$BacktraceSink")
      converter.module.has_function_with_body?(call.not_nil!.method_name).should be_true
    end

    it "reuses a materialized splat body for its packed tuple ABI" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class PackedSplatReceiver
          def match?(*sets : String) : Bool
            true
          end
        end

        def packed_splat_probe(receiver : PackedSplatReceiver, sets : Tuple(String)) : Bool
          receiver.match?(*sets)
        end

        packed_splat_probe(PackedSplatReceiver.new, {"set"})
      CRYSTAL

      function = converter.module.functions.find { |candidate| candidate.name.starts_with?("packed_splat_probe$") }
      function.should_not be_nil
      call = function.not_nil!.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call)).find do |candidate|
        candidate.method_name.includes?("PackedSplatReceiver#match?")
      end
      call.should_not be_nil
      call.not_nil!.method_name = "PackedSplatReceiver#match?$Tuple(String)_splat"

      converter.flush_pending_functions

      repaired = function.not_nil!.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call)).find do |candidate|
        candidate.method_name.includes?("PackedSplatReceiver#match?")
      end
      repaired.should_not be_nil
      repaired.not_nil!.method_name.should eq("PackedSplatReceiver#match?$String_splat")
      converter.module.has_function_with_body?(repaired.not_nil!.method_name).should be_true
    end

    it "synthesizes zero-arg allocators for generic structs before MIR lowering" do
      code = <<-CRYSTAL
        struct SmallVec(T, N)
          @arr : Array(T)

          def initialize
            @arr = Array(T).new(N)
          end

          def size : Int32
            @arr.size
          end
        end

        def probe
          vec = SmallVec(Int32, 64).new
          vec.size
        end
      CRYSTAL

      converter = lower_program(code)
      func = converter.module.functions.find { |f| f.name.split("$").first == "probe" }
      func.should_not be_nil

      text = hir_text(func.not_nil!)
      text.should contain("call SmallVec(Int32, 64).new()")

      new_func = converter.module.functions.find { |f| f.name == "SmallVec(Int32, 64).new" }
      new_func.should_not be_nil

      new_text = hir_text(new_func.not_nil!)
      new_text.should contain("SmallVec(Int32, 64)#initialize()")
    end

    it "preserves typed default literals in lowered function params" do
      func = lower_function("def foo(x : Int32 = 1)\n  x\nend")

      func.params.size.should eq(1)
      func.params[0].name.should eq("x")
      func.params[0].default_literal.should eq("1")
    end

    it "prefers non-block overload when no block is passed" do
      code = <<-CRYSTAL
        class Foo
          def self.malloc(size : Int32 = 1)
            size
          end

          def self.malloc(size : Int32, & : Int32 -> Int32)
            yield size
          end
        end

        def bar
          Foo.malloc
        end
      CRYSTAL

      converter = lower_program(code)
      func = converter.module.functions.find { |f| f.name.split("$").first == "bar" }
      func.should_not be_nil

      call = func.not_nil!.blocks.flat_map(&.instructions)
        .find { |inst| inst.is_a?(Adamas::HIR::Call) }
      call.should_not be_nil
      call_name = call.not_nil!.as(Adamas::HIR::Call).method_name
      call_name.should contain("Foo.malloc$Int32")
      call_name.should_not contain("block")
    end

    it "lowers method call with args" do
      func = lower_function("def foo; puts(1, 2); end")
      text = hir_text(func)

      text.should contain("call")
    end

    it "lowers free function call" do
      func = lower_function("def foo; puts(1); end")
      text = hir_text(func)

      text.should contain("extern_call")
      text.should contain("__adamas_print_int32_ln")
    end

    it "lowers index access" do
      func = lower_function("def foo; arr[0]; end")
      text = hir_text(func)

      # For unknown types, index access becomes a method call to []
      # (IndexGet is only used for known array types and pointer types)
      text.should contain("call")
      text.should contain("[]")
    end

    it "lowers index assignment" do
      func = lower_function("def foo; arr[0] = 1; end")
      text = hir_text(func)

      # For unknown types, index assignment becomes a method call to []=
      # (IndexSet is only used for known array types)
      text.should contain("call")
      text.should contain("[]=")
    end

    it "lowers chained calls" do
      func = lower_function("def foo; a.b.c; end")
      text = hir_text(func)

      text.scan(/call/).size.should be >= 2
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POSITIVE TESTS: CLOSURES
  # ═══════════════════════════════════════════════════════════════════════════

  describe "closure lowering" do
    it "lowers proc literal" do
      func = lower_function("def foo; -> { 1 }; end")
      text = hir_text(func)

      text.should contain("func_pointer")
      text.should contain("__crystal_proc_")
    end

    it "lowers proc with parameters" do
      func = lower_function("def foo; ->(x : Int32) { x + 1 }; end")
      text = hir_text(func)

      text.should contain("func_pointer")
      text.should contain("__crystal_proc_")
    end

    it "narrows a nilable capture across a proc short-circuit" do
      _func, converter = lower_function_with_converter(<<-CRYSTAL)
        def probe(values : Set(String)?)
          predicate = ->(name : String) { values && values.includes?(name) }
          predicate.call("x")
        end
      CRYSTAL

      proc_func = converter.module.functions.find(&.name.starts_with?("__crystal_proc_"))
      proc_func.should_not be_nil
      call_names = proc_func.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call).try(&.method_name)
      end

      call_names.should contain("Set(String)#includes?$String")
      call_names.none? { |name| name.starts_with?("Nil#includes?$") }.should be_true
    end

    it "narrows a nilable capture across a materialized block short-circuit" do
      converter = lower_program(<<-CRYSTAL)
        def invoke(&block : String -> Bool)
          block.call("x")
        end

        def probe(values : Set(String)?)
          invoke { |name| values && values.includes?(name) }
        end
      CRYSTAL

      proc_func = converter.module.functions.find(&.name.starts_with?("__crystal_block_proc_"))
      proc_func.should_not be_nil
      call_names = proc_func.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call).try(&.method_name)
      end

      call_names.should contain("Set(String)#includes?$String")
      call_names.none? { |name| name.starts_with?("Nil#includes?$") }.should be_true
    end

    it "narrows a nilable capture across a short-circuit condition" do
      _func, converter = lower_function_with_converter(<<-CRYSTAL)
        def probe(values : Set(String)?)
          predicate = ->(name : String) do
            if values && values.includes?(name)
              true
            else
              false
            end
          end
          predicate.call("x")
        end
      CRYSTAL

      proc_func = converter.module.functions.find(&.name.starts_with?("__crystal_proc_"))
      proc_func.should_not be_nil
      call_names = proc_func.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call).try(&.method_name)
      end

      call_names.should contain("Set(String)#includes?$String")
      call_names.none? { |name| name.starts_with?("Nil#includes?$") }.should be_true
    end

    it "narrows the first captured argument inside a truthy branch" do
      converter = lower_program(<<-CRYSTAL)
        class CaptureIfProbe
          def consume(value : UInt32) : UInt32
            value
          end

          def probe(value : UInt32?) : UInt32
            reader = -> do
              if value
                consume(value)
              else
                0_u32
              end
            end
            reader.call
          end
        end
      CRYSTAL

      proc_func = converter.module.functions.find do |candidate|
        candidate.name.starts_with?("__crystal_proc_") &&
          candidate.blocks.flat_map(&.instructions).any? do |instruction|
            instruction.as?(Adamas::HIR::Call).try(&.method_name.starts_with?("CaptureIfProbe#consume$"))
          end
      end
      proc_func.should_not be_nil

      consume_calls = proc_func.not_nil!.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call)).select do |call|
        call.method_name.starts_with?("CaptureIfProbe#consume$")
      end
      consume_calls.size.should eq(1)
      consume_calls.first.method_name.should eq("CaptureIfProbe#consume$UInt32")

      argument_id = consume_calls.first.args.first
      argument = proc_func.not_nil!.params.find { |param| param.id == argument_id } ||
                 proc_func.not_nil!.blocks.flat_map(&.instructions).find { |instruction| instruction.id == argument_id }
      argument.should_not be_nil
      converter.__test_get_type_name_from_ref(argument.not_nil!.type).should eq("UInt32")
    end

    it "narrows a boxed captured local inside a direct truthy branch" do
      converter = lower_program(<<-CRYSTAL)
        class BoxedCaptureIfProbe
          def consume(value : UInt32) : UInt32
            value
          end

          def probe(value : UInt32?) : UInt32
            writer = -> do
              value = nil
            end
            if value
              consume(value)
            else
              0_u32
            end
          end
        end
      CRYSTAL

      probe_func = converter.module.functions.find do |candidate|
        candidate.name.starts_with?("BoxedCaptureIfProbe#probe$")
      end
      probe_func.should_not be_nil

      consume_calls = probe_func.not_nil!.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call)).select do |call|
        call.method_name.starts_with?("BoxedCaptureIfProbe#consume$")
      end
      consume_calls.should_not be_empty
      consume_calls.all? do |call|
        call.method_name == "BoxedCaptureIfProbe#consume$UInt32"
      end.should be_true
    end

    it "renews a captured truthy narrowing through a nested direct condition" do
      converter = lower_program(<<-CRYSTAL)
        class NestedCaptureIfProbe
          def consume(value : UInt32) : UInt32
            value
          end

          def probe(value : UInt32?) : UInt32
            reader = -> do
              if value
                if value
                  consume(value)
                else
                  0_u32
                end
              else
                0_u32
              end
            end
            reader.call
          end
        end
      CRYSTAL

      proc_func = converter.module.functions.find do |candidate|
        candidate.name.starts_with?("__crystal_proc_") &&
          candidate.blocks.flat_map(&.instructions).any? do |instruction|
            instruction.as?(Adamas::HIR::Call).try(&.method_name.starts_with?("NestedCaptureIfProbe#consume$"))
          end
      end
      proc_func.should_not be_nil

      consume_calls = proc_func.not_nil!.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call)).select do |call|
        call.method_name.starts_with?("NestedCaptureIfProbe#consume$")
      end
      consume_calls.size.should eq(1)
      consume_calls.first.method_name.should eq("NestedCaptureIfProbe#consume$UInt32")
    end

    it "narrows independent nested captured conditions" do
      converter = lower_program(<<-CRYSTAL)
        class NestedCaptureNamesProbe
          def consume(value : UInt32) : UInt32
            value
          end

          def probe(value : UInt32?, other : UInt32?) : UInt32
            reader = -> do
              if value
                if other
                  consume(other)
                else
                  0_u32
                end
              else
                0_u32
              end
            end
            reader.call
          end
        end
      CRYSTAL

      proc_func = converter.module.functions.find do |candidate|
        candidate.name.starts_with?("__crystal_proc_") &&
          candidate.blocks.flat_map(&.instructions).any? do |instruction|
            instruction.as?(Adamas::HIR::Call).try(&.method_name.starts_with?("NestedCaptureNamesProbe#consume$"))
          end
      end
      proc_func.should_not be_nil

      consume_calls = proc_func.not_nil!.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call)).select do |call|
        call.method_name.starts_with?("NestedCaptureNamesProbe#consume$")
      end
      consume_calls.should_not be_empty
      consume_calls.all? do |call|
        call.method_name == "NestedCaptureNamesProbe#consume$UInt32"
      end.should be_true
    end

    it "reloads a captured truthy value after an aliasing call" do
      converter = lower_program(<<-CRYSTAL)
        class CaptureIfAliasMutationProbe
          def consume(value : UInt32) : UInt32
            value
          end

          def probe(value : UInt32?) : UInt32
            writer = -> do
              value = nil
            end
            reader = -> do
              if value
                writer.call
                if value
                  consume(value)
                else
                  0_u32
                end
              else
                0_u32
              end
            end
            reader.call
          end
        end
      CRYSTAL

      proc_func = converter.module.functions.find do |candidate|
        candidate.name.starts_with?("__crystal_proc_") &&
          candidate.blocks.flat_map(&.instructions).any? do |instruction|
            instruction.as?(Adamas::HIR::Call).try(&.method_name.starts_with?("CaptureIfAliasMutationProbe#consume$"))
          end
      end
      proc_func.should_not be_nil

      instructions = proc_func.not_nil!.blocks.flat_map(&.instructions)
      writer_call = instructions.compact_map(&.as?(Adamas::HIR::Call)).find do |call|
        call.method_name.starts_with?("Proc") && call.method_name.includes?("#call")
      end
      writer_call.should_not be_nil

      loads = instructions.compact_map(&.as?(Adamas::HIR::PointerLoad))
      loads.any? do |condition_load|
        condition_load.id < writer_call.not_nil!.id && loads.any? do |reload|
          reload.pointer == condition_load.pointer && reload.id > writer_call.not_nil!.id
        end
      end.should be_true
    end

    it "keeps a captured truthy narrowing across an unrelated field write" do
      converter = lower_program(<<-CRYSTAL)
        class CaptureIfUnrelatedFieldWriteProbe
          @other : Int32 = 0

          def consume(value : UInt32) : UInt32
            value
          end

          def probe(value : UInt32?) : UInt32
            reader = -> do
              if value
                @other = 1
                consume(value)
              else
                0_u32
              end
            end
            reader.call
          end
        end
      CRYSTAL

      proc_func = converter.module.functions.find do |candidate|
        candidate.name.starts_with?("__crystal_proc_") &&
          candidate.blocks.flat_map(&.instructions).any? do |instruction|
            instruction.as?(Adamas::HIR::Call).try(&.method_name.starts_with?("CaptureIfUnrelatedFieldWriteProbe#consume$"))
          end
      end
      proc_func.should_not be_nil

      consume_calls = proc_func.not_nil!.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call)).select do |call|
        call.method_name.starts_with?("CaptureIfUnrelatedFieldWriteProbe#consume$")
      end
      consume_calls.should_not be_empty
      consume_calls.all? do |call|
        call.method_name == "CaptureIfUnrelatedFieldWriteProbe#consume$UInt32"
      end.should be_true
    end

    it "does not apply an outer capture proof to a same-name block parameter" do
      converter = lower_program(<<-CRYSTAL)
        class CaptureIfShadowProbe
          def consume(value : UInt32) : UInt32
            value
          end

          def probe(value : UInt32?) : UInt32
            reader = -> do
              if value
                [1_u32].each do |value|
                  if value
                    consume(value)
                  end
                end
                0_u32
              else
                0_u32
              end
            end
            reader.call
          end
        end
      CRYSTAL

      consume_calls = converter.module.functions.flat_map(&.blocks).flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end.select do |call|
        call.method_name.starts_with?("CaptureIfShadowProbe#consume$")
      end
      consume_calls.size.should eq(1)
      consume_calls.first.method_name.should eq("CaptureIfShadowProbe#consume$UInt32")
    end

    it "reads a raw block parameter that shadows a closure cell" do
      converter = lower_program(<<-CRYSTAL)
        class CaptureIfRawShadowProbe
          def consume(value : UInt32) : UInt32
            value
          end

          def each_once(&block : UInt32 ->)
            yield 1_u32
          end

          def probe(value : UInt32?) : UInt32
            each_once do
              value = nil
            end
            each_once do |value|
              if value
                consume(value)
              else
                0_u32
              end
            end
            0_u32
          end
        end
      CRYSTAL

      proc_func = converter.module.functions.find do |candidate|
        candidate.name.starts_with?("__crystal_block_proc_") &&
          candidate.params.any? { |param| param.name == "value" } &&
          candidate.blocks.flat_map(&.instructions).any? do |instruction|
            instruction.as?(Adamas::HIR::Call).try(&.method_name.starts_with?("CaptureIfRawShadowProbe#consume$"))
          end
      end
      proc_func.should_not be_nil

      parameter = proc_func.not_nil!.params.find { |param| param.name == "value" }
      parameter.should_not be_nil
      instructions = proc_func.not_nil!.blocks.flat_map(&.instructions)
      consume_call = instructions.compact_map(&.as?(Adamas::HIR::Call)).find do |call|
        call.method_name.starts_with?("CaptureIfRawShadowProbe#consume$")
      end
      consume_call.should_not be_nil

      source_id = consume_call.not_nil!.args.first
      reaches_parameter = false
      reaches_closure_cell = false
      visited = Set(Adamas::HIR::ValueId).new
      loop do
        if source_id == parameter.not_nil!.id
          reaches_parameter = true
          break
        end
        break unless visited.add?(source_id)
        source = instructions.find { |instruction| instruction.id == source_id }
        break unless source
        case source
        when Adamas::HIR::Copy
          source_id = source.source
        when Adamas::HIR::UnionUnwrap
          source_id = source.union_value
        when Adamas::HIR::ClassVarGet
          reaches_closure_cell = source.class_name == "__closure" &&
                                 source.var_name.starts_with?("__closure_cell_")
          break
        else
          break
        end
      end

      reaches_parameter.should be_true
      reaches_closure_cell.should be_false
    end

    it "reads an inline block parameter that shadows a closure cell" do
      converter = lower_program(<<-CRYSTAL)
        class CaptureIfInlineRawShadowProbe
          def consume(value : UInt32) : UInt32
            value
          end

          def each_once(&block : UInt32 ->)
            yield 1_u32
          end

          def probe(value : UInt32?) : UInt32
            each_once do
              value = nil
            end
            each_once do
              [1_u32].each do |value|
                if value
                  consume(value)
                else
                  0_u32
                end
              end
            end
            0_u32
          end
        end
      CRYSTAL

      proc_func = converter.module.functions.find do |candidate|
        candidate.name.starts_with?("__crystal_block_proc_") &&
          candidate.params.none? { |param| param.name == "value" } &&
          candidate.blocks.flat_map(&.instructions).any? do |instruction|
            instruction.as?(Adamas::HIR::Call).try(&.method_name.starts_with?("CaptureIfInlineRawShadowProbe#consume$"))
          end
      end
      proc_func.should_not be_nil

      instructions = proc_func.not_nil!.blocks.flat_map(&.instructions)
      consume_call = instructions.compact_map(&.as?(Adamas::HIR::Call)).find do |call|
        call.method_name.starts_with?("CaptureIfInlineRawShadowProbe#consume$")
      end
      consume_call.should_not be_nil

      source_id = consume_call.not_nil!.args.first
      reaches_yielded_value = false
      reaches_closure_cell = false
      visited = Set(Adamas::HIR::ValueId).new
      loop do
        break unless visited.add?(source_id)
        source = instructions.find { |instruction| instruction.id == source_id }
        break unless source
        case source
        when Adamas::HIR::Copy
          source_id = source.source
        when Adamas::HIR::UnionUnwrap
          source_id = source.union_value
        when Adamas::HIR::Literal
          reaches_yielded_value = source.type == Adamas::HIR::TypeRef::UINT32
          break
        when Adamas::HIR::IndexGet
          reaches_yielded_value = source.type == Adamas::HIR::TypeRef::UINT32
          break
        when Adamas::HIR::ClassVarGet
          reaches_closure_cell = source.class_name == "__closure" &&
                                 source.var_name.starts_with?("__closure_cell_")
          break
        else
          break
        end
      end

      reaches_yielded_value.should be_true
      reaches_closure_cell.should be_false
    end

    it "does not write an inline block parameter through a same-name closure cell" do
      converter = lower_program(<<-CRYSTAL)
        class CaptureIfInlineWriteShadowProbe
          def consume(value : UInt32) : UInt32
            value
          end

          def each_once(&block : UInt32 ->)
            yield 1_u32
          end

          def probe(value : UInt32?) : UInt32
            each_once do
              value = nil
            end
            each_once do
              [1_u32].each do |value|
                value = 2_u32
                consume(value)
              end
            end
            0_u32
          end
        end
      CRYSTAL

      proc_func = converter.module.functions.find do |candidate|
        candidate.name.starts_with?("__crystal_block_proc_") &&
          candidate.blocks.flat_map(&.instructions).any? do |instruction|
            instruction.as?(Adamas::HIR::Call).try(&.method_name.starts_with?("CaptureIfInlineWriteShadowProbe#consume$"))
          end
      end
      proc_func.should_not be_nil

      instructions = proc_func.not_nil!.blocks.flat_map(&.instructions)
      consume_call = instructions.compact_map(&.as?(Adamas::HIR::Call)).find do |call|
        call.method_name.starts_with?("CaptureIfInlineWriteShadowProbe#consume$")
      end
      consume_call.should_not be_nil
      consume_call.not_nil!.method_name.should eq("CaptureIfInlineWriteShadowProbe#consume$UInt32")
      instructions.compact_map(&.as?(Adamas::HIR::ClassVarSet)).none? do |write|
        write.class_name == "__closure" && write.var_name.starts_with?("__closure_cell_")
      end.should be_true
    end

    it "consumes a truthy branch capture narrowing after one direct read" do
      converter = lower_program(<<-CRYSTAL)
        class CaptureIfSingleUseProbe
          def probe(value : UInt32?) : UInt32?
            reader = -> do
              if value
                first = value
                value
              else
                nil
              end
            end
            reader.call
          end
        end
      CRYSTAL

      proc_func = converter.module.functions.find(&.name.starts_with?("__crystal_proc_"))
      proc_func.should_not be_nil
      instructions = proc_func.not_nil!.blocks.flat_map(&.instructions)
      loads = instructions.compact_map(&.as?(Adamas::HIR::PointerLoad))
      condition_unwrap = instructions.compact_map(&.as?(Adamas::HIR::UnionUnwrap)).find do |unwrap|
        loads.any? { |load| load.id == unwrap.union_value }
      end
      condition_unwrap.should_not be_nil

      condition_load = loads.find { |load| load.id == condition_unwrap.not_nil!.union_value }
      condition_load.should_not be_nil
      loads.any? do |load|
        load.pointer == condition_load.not_nil!.pointer && load.id > condition_unwrap.not_nil!.id
      end.should be_true
    end

    it "invalidates a truthy branch capture narrowing before assignment" do
      converter = lower_program(<<-CRYSTAL)
        class CaptureIfMutationProbe
          def probe(value : UInt32?) : UInt32?
            reader = -> do
              if value
                value = nil
                value
              else
                nil
              end
            end
            reader.call
          end
        end
      CRYSTAL

      proc_func = converter.module.functions.find(&.name.starts_with?("__crystal_proc_"))
      proc_func.should_not be_nil
      instructions = proc_func.not_nil!.blocks.flat_map(&.instructions)
      store = instructions.compact_map(&.as?(Adamas::HIR::PointerStore)).first?
      store.should_not be_nil

      instructions.compact_map(&.as?(Adamas::HIR::PointerLoad)).any? do |load|
        load.pointer == store.not_nil!.pointer && load.id > store.not_nil!.id
      end.should be_true
    end

    it "consumes a boxed receiver narrowing before lowering mutating call arguments" do
      _func, converter = lower_function_with_converter(<<-CRYSTAL)
        def probe(values : Set(String)?)
          reader = -> do
            values && values.includes?(begin
              values = nil
              "x"
            end)
            values
          end
          reader.call
        end
      CRYSTAL

      proc_func = converter.module.functions.find(&.name.starts_with?("__crystal_proc_"))
      proc_func.should_not be_nil
      instructions = proc_func.not_nil!.blocks.flat_map(&.instructions)
      calls = instructions.compact_map(&.as?(Adamas::HIR::Call))
      includes_call = calls.find { |call| call.method_name == "Set(String)#includes?$String" }
      includes_call.should_not be_nil
      calls.none? { |call| call.method_name.starts_with?("Nil#includes?$") }.should be_true

      store = instructions.compact_map(&.as?(Adamas::HIR::PointerStore)).first?
      store.should_not be_nil
      receiver = instructions.find { |instruction| instruction.id == includes_call.not_nil!.receiver_value }
      receiver.not_nil!.should be_a(Adamas::HIR::Copy)
      receiver.not_nil!.id.should be < store.not_nil!.id
      store.not_nil!.id.should be < includes_call.not_nil!.id
      instructions.compact_map(&.as?(Adamas::HIR::PointerLoad)).any? do |load|
        load.pointer == store.not_nil!.pointer && load.id > store.not_nil!.id
      end.should be_true
    end

    it "lowers block argument" do
      func = lower_function("def foo; each { |x| x }; end")
      text = hir_text(func)

      text.should contain("call")
      text.should contain("with_block")
    end

    it "lowers standalone proc literals without make_closure wrappers" do
      func = lower_function("def foo; -> { 1 }; end")

      closure = func.blocks.flat_map(&.instructions).find { |i| i.is_a?(Adamas::HIR::MakeClosure) }
      closure.should be_nil

      func.blocks.flat_map(&.instructions).any? { |i| i.is_a?(Adamas::HIR::FuncPointer) }.should be_true
    end

    it "writes through a captured local when tuple destructuring reassigns it" do
      func, _converter = lower_function_with_converter(<<-CRYSTAL)
        def probe(pair : Tuple(Int32, Int32)) : Int32
          first = 0
          reader = -> { first }
          first, second = pair
          reader.call + second
        end
      CRYSTAL

      instructions = func.blocks.flat_map(&.instructions)
      stores = instructions.compact_map { |instruction| instruction.as?(Adamas::HIR::PointerStore) }
      tuple_element_ids = instructions.compact_map { |instruction| instruction.as?(Adamas::HIR::IndexGet) }.map(&.id)

      stores.size.should be >= 2
      stores.any? { |store| tuple_element_ids.includes?(store.value) }.should be_true
    end

    it "rebinds a same-typed stale box before reading the restored local" do
      arena, roots = parse("first")
      target_expr = roots.first
      converter = Adamas::HIR::AstToHir.new(arena)
      func, missing_before_assignment, visible_after_assignment = converter.__test_rebind_stale_box_same_type(arena, target_expr)

      missing_before_assignment.should be_true
      visible_after_assignment.should be_true
      text = hir_text(func)
      text.should_not contain("local \"first\" : Void")
      text.should contain("ptr_load")
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POSITIVE TESTS: COLLECTIONS
  # ═══════════════════════════════════════════════════════════════════════════

  describe "collection lowering" do
    it "lowers empty array" do
      func = lower_function("def foo; [] of Int32; end")
      text = hir_text(func)

      text.should contain("array_literal")
    end

    it "lowers array literal" do
      func = lower_function("def foo; [1, 2, 3]; end")
      text = hir_text(func)

      text.should contain("array_literal")
    end

    it "lowers hash literal" do
      func = lower_function("def foo; {\"a\" => 1}; end")
      text = hir_text(func)

      # Hash literals now lower to Hash.new() + []= calls
      text.should contain("Hash")
    end

    it "lowers tuple literal" do
      func = lower_function("def foo; {1, \"a\"}; end")
      text = hir_text(func)

      text.should contain("allocate")
    end

    it "matches named-tuple equality operands by key instead of storage order" do
      func, converter = lower_function_with_converter(<<-CRYSTAL)
        def foo
          left = {a: 1, b: 2_i64}
          right = {b: 2_i64, a: 1}
          left == right
        end
      CRYSTAL

      instructions = func.blocks.flat_map(&.instructions)
      instructions.compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
        .none? { |call| call.method_name.includes?("NamedTuple(") && call.method_name.includes?("#==") }
        .should be_true

      named_tuple_allocations = instructions.compact_map do |instruction|
        allocation = instruction.as?(Adamas::HIR::Allocate)
        next unless allocation
        descriptor = converter.module.get_type_descriptor(allocation.type)
        allocation if descriptor && descriptor.kind == Adamas::HIR::TypeKind::NamedTuple
      end
      named_tuple_allocations.size.should eq(2)

      literal_indices = instructions.compact_map { |instruction| instruction.as?(Adamas::HIR::Literal) }
        .to_h { |literal| {literal.id, literal.int_value.to_i32} }
      value_types = instructions.compact_map { |instruction| instruction.as?(Adamas::HIR::Value) }
        .to_h { |value| {value.id, value.type} }
      left_indices = instructions.compact_map { |instruction| instruction.as?(Adamas::HIR::IndexGet) }
        .select { |get| value_types[get.object]? == named_tuple_allocations[0].type }
        .map { |get| literal_indices[get.index] }
      right_indices = instructions.compact_map { |instruction| instruction.as?(Adamas::HIR::IndexGet) }
        .select { |get| value_types[get.object]? == named_tuple_allocations[1].type }
        .map { |get| literal_indices[get.index] }

      left_indices.should eq([0, 1])
      right_indices.should eq([1, 0])
    end

    it "rejects named-tuple equality when key sets differ" do
      func = lower_function(<<-CRYSTAL)
        def foo
          left = {a: 1}
          right = {b: 1}
          left == right
        end
      CRYSTAL

      text = hir_text(func)
      text.should contain("literal false")
      text.should_not contain("call NamedTuple(")
    end

    it "rejects named-tuple equality when one side has extra keys" do
      func = lower_function(<<-CRYSTAL)
        def foo
          left = {a: 1}
          right = {a: 1, b: 2}
          left == right
        end
      CRYSTAL

      text = hir_text(func)
      text.should contain("literal false")
      text.should_not contain("index_get")
      text.should_not contain("call NamedTuple(")
    end

    it "short-circuits structural tuple equality before later element calls" do
      func = lower_function(<<-CRYSTAL)
        class EqualityProbe
          def ==(other : EqualityProbe) : Bool
            true
          end
        end

        def foo(left : Tuple(Int32, EqualityProbe), right : Tuple(Int32, EqualityProbe))
          left == right
        end
      CRYSTAL

      equality_call_block = func.blocks.find do |block|
        block.instructions.any? do |instruction|
          call = instruction.as?(Adamas::HIR::Call)
          call && call.method_name.includes?("EqualityProbe#==")
        end
      end
      equality_call_block.should_not be_nil

      first_comparison_branch = func.blocks.find do |block|
        branch = block.terminator.as?(Adamas::HIR::Branch)
        branch && branch.then_block == equality_call_block.not_nil!.id
      end
      first_comparison_branch.should_not be_nil
    end

    it "preserves element case equality for Tuple#===" do
      func = lower_function(<<-CRYSTAL)
        class CaseEqualityProbe
          def ==(other : CaseEqualityProbe) : Bool
            false
          end

          def ===(other : CaseEqualityProbe) : Bool
            true
          end
        end

        def foo(left : Tuple(CaseEqualityProbe), right : Tuple(CaseEqualityProbe))
          left === right
        end
      CRYSTAL

      calls = func.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end
      calls.any? { |call| call.method_name.includes?("CaseEqualityProbe#===") }.should be_true
      calls.none? { |call| call.method_name.includes?("CaseEqualityProbe#==$") }.should be_true
    end

    it "rejects equality between tuple and named-tuple structural carriers" do
      func = lower_function(<<-CRYSTAL)
        def foo
          left = {a: 1}
          right = {1}
          left == right
        end
      CRYSTAL

      text = hir_text(func)
      text.should contain("literal false")
      text.should_not contain("call NamedTuple(")
    end

    it "lowers range" do
      func = lower_function("def foo; 1..10; end")
      text = hir_text(func)

      text.should contain("allocate")
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POSITIVE TESTS: TYPE OPERATIONS
  # ═══════════════════════════════════════════════════════════════════════════

  describe "type operation lowering" do
    it "lowers as cast" do
      func = lower_function("def foo(x); x as Int32; end")
      text = hir_text(func)

      text.should contain("cast")
    end

    it "lowers as? safe cast" do
      func = lower_function("def foo(x); x as? Int32; end")
      text = hir_text(func)

      text.should contain("is_a")
      text.should contain("__adamas_select_ptr")
    end

    it "lowers is_a? check" do
      func = lower_function("def foo(x); x.is_a?(Int32); end")
      text = hir_text(func)

      # Parser produces IsANode for x.is_a?(Type)
      text.should contain("is_a")
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # NEGATIVE TESTS: EDGE CASES
  # ═══════════════════════════════════════════════════════════════════════════

  describe "edge cases" do
    it "handles empty function body" do
      func = lower_function("def foo; end")

      # Should still have entry block with return
      func.blocks.size.should be >= 1
    end

    it "handles deeply nested expressions" do
      func = lower_function("def foo; ((((1 + 2) + 3) + 4) + 5); end")
      text = hir_text(func)

      text.scan(/binop Add/).size.should eq(4)
    end

    it "handles multiple statements" do
      func = lower_function("def foo; x = 1; y = 2; x + y; end")
      text = hir_text(func)

      text.should contain("x")
      text.should contain("y")
      text.should contain("binop Add")
    end

    it "handles variable shadowing in nested scope" do
      func = lower_function("def foo; x = 1; if true; x = 2; end; x; end")
      text = hir_text(func)

      # Both assignments should be present
      text.scan(/local/).size.should be >= 1
    end

    it "handles complex control flow" do
      func = lower_function(<<-CRYSTAL)
        def foo(n)
          result = 0
          while n > 0
            if n % 2 == 0
              result = result + n
            end
            n = n - 1
          end
          result
        end
      CRYSTAL

      text = hir_text(func)
      text.should contain("branch")
      text.should contain("jump")
    end

    it "handles method with block and regular args" do
      func = lower_function("def foo; map(1, 2) { |x| x * 2 }; end")
      text = hir_text(func)

      text.should contain("call")
      text.should contain("with_block")
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # NEGATIVE TESTS: ERROR HANDLING
  # ═══════════════════════════════════════════════════════════════════════════

  describe "error handling" do
    it "lowers declaration nodes to nil" do
      # Declaration nodes are not first-class runtime values in the current
      # lowering path, so lowering them in isolation terminates the synthetic
      # test function as unreachable rather than materializing a Nil literal.

      arena, exprs = parse("class Foo; end")
      converter = Adamas::HIR::AstToHir.new(arena)

      class_expr = exprs.first
      class_node = arena[class_expr]

      func = converter.module.create_function("test", Adamas::HIR::TypeRef::VOID)
      ctx = Adamas::HIR::LoweringContext.new(func, converter.module, arena)

      converter.lower_node(ctx, class_node)
      hir_text(func).should contain("unreachable")
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # LIFETIME TESTS
  # ═══════════════════════════════════════════════════════════════════════════

  describe "lifetime annotations" do
    it "marks literals as StackLocal" do
      func = lower_function("def foo; 42; end")

      literal = func.blocks[0].instructions.first
      literal.lifetime.should eq(Adamas::HIR::LifetimeTag::StackLocal)
    end

    it "marks parameters as HeapEscape (conservative)" do
      func = lower_function("def foo(x); x; end")

      func.params[0].lifetime.should eq(Adamas::HIR::LifetimeTag::HeapEscape)
    end

    it "marks array literals as StackLocal initially" do
      func = lower_function("def foo; [1, 2, 3]; end")

      arr = func.blocks.flat_map(&.instructions).find { |i| i.is_a?(Adamas::HIR::ArrayLiteral) }
      arr.should_not be_nil
      arr.not_nil!.lifetime.should eq(Adamas::HIR::LifetimeTag::StackLocal)
    end

    it "marks class var access as GlobalEscape" do
      func = lower_function("def foo; @@x; end")

      class_var = func.blocks.flat_map(&.instructions).find { |i| i.is_a?(Adamas::HIR::ClassVarGet) }
      class_var.should_not be_nil
      class_var.not_nil!.lifetime.should eq(Adamas::HIR::LifetimeTag::GlobalEscape)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SCOPE TESTS
  # ═══════════════════════════════════════════════════════════════════════════

  describe "scope handling" do
    it "creates function scope" do
      func = lower_function("def foo; 1; end")

      func.scopes.size.should be >= 1
      func.scopes[0].kind.should eq(Adamas::HIR::ScopeKind::Function)
    end

    it "creates block scope for if" do
      func = lower_function("def foo; if true; 1; end; end")

      block_scopes = func.scopes.select { |s| s.kind == Adamas::HIR::ScopeKind::Block }
      block_scopes.size.should be >= 1
    end

    it "creates loop scope for while" do
      func = lower_function("def foo; while true; 1; end; end")

      loop_scopes = func.scopes.select { |s| s.kind == Adamas::HIR::ScopeKind::Loop }
      loop_scopes.size.should be >= 1
    end

    it "keeps proc literals as standalone functions without parent closure scopes" do
      func = lower_function("def foo; -> { 1 }; end")

      closure_scopes = func.scopes.select { |s| s.kind == Adamas::HIR::ScopeKind::Closure }
      closure_scopes.should be_empty
    end

    it "nests scopes correctly" do
      func = lower_function("def foo; if true; while false; 1; end; end; end")

      # Should have function > block > loop nesting
      func.scopes.size.should be >= 3
    end
  end

  describe "module mixin return inference" do
    it "prefers concrete self type for module-like return annotations" do
      code = <<-CRYSTAL
        module M
          def returns_self : M
            self
          end
        end

        class Box
          include M
        end
      CRYSTAL

      converter = lower_program(code)
      # Module methods get arity suffix when lowered for including class
      func = converter.module.functions.find { |f| f.name.starts_with?("Box#returns_self") }
      func.should_not be_nil

      box_type = converter.class_info["Box"].type_ref
      func.not_nil!.return_type.should eq(box_type)
    end
  end

  describe "module-typed locals" do
    it "keeps concrete initializer types for module-annotated locals" do
      code = <<-CRYSTAL
        module M
          def value : M
            self
          end
        end

        class Box
          include M
        end

        def foo
          x : M = Box.new
          x.value
        end
      CRYSTAL

      converter = lower_program(code)
      func = converter.module.functions.find { |f| f.name.split("$").first == "foo" }
      func.should_not be_nil

      call = func.not_nil!.blocks.flat_map(&.instructions)
        .find { |inst| inst.is_a?(Adamas::HIR::Call) && inst.as(Adamas::HIR::Call).method_name.includes?("#value") }
      call.should_not be_nil

      recv_id = call.not_nil!.as(Adamas::HIR::Call).receiver
      recv_id.should_not be_nil

      recv = func.not_nil!.blocks.flat_map(&.instructions).find { |inst| inst.id == recv_id }
      recv.should_not be_nil

      box_type = converter.class_info["Box"].type_ref
      recv.not_nil!.type.should eq(box_type)
    end

    it "prefers concrete assignment when includers are ambiguous" do
      code = <<-CRYSTAL
        module M
          def value : Int32
            1
          end
        end

        class Box
          include M
          def value : Int32
            2
          end
        end

        class Bag
          include M
          def value : Int32
            3
          end
        end

        def foo(x : M)
          x = Box.new
          x.value
        end
      CRYSTAL

      converter = lower_program(code)
      func = converter.module.functions.find { |f| f.name.split("$").first == "foo" }
      func.should_not be_nil

      call = func.not_nil!.blocks.flat_map(&.instructions)
        .find { |inst| inst.is_a?(Adamas::HIR::Call) && inst.as(Adamas::HIR::Call).method_name.includes?("#value") }
      call.should_not be_nil

      call.not_nil!.as(Adamas::HIR::Call).method_name.should contain("Box#value")
    end
  end

  describe "module-typed receivers" do
    it "resolves unique includer methods for module-typed params" do
      code = <<-CRYSTAL
        module M
          def value : Int32
            1
          end
        end

        class Box
          include M
        end

        def foo(x : M)
          x.value
        end
      CRYSTAL

      converter = lower_program(code)
      func = converter.module.functions.find { |f| f.name.split("$").first == "foo" }
      func.should_not be_nil

      call = func.not_nil!.blocks.flat_map(&.instructions)
        .find { |inst| inst.is_a?(Adamas::HIR::Call) }
      call.should_not be_nil

      call.not_nil!.as(Adamas::HIR::Call).method_name.should contain("Box#value")
    end

    it "does not guess when includers are ambiguous" do
      code = <<-CRYSTAL
        module M
        end

        class Box
          include M
          def value : Int32
            1
          end
        end

        class Bag
          include M
          def value : Int32
            2
          end
        end

        def foo(x : M)
          x.value
        end
      CRYSTAL

      converter = lower_program(code)
      func = converter.module.functions.find { |f| f.name.split("$").first == "foo" }
      func.should_not be_nil

      call = func.not_nil!.blocks.flat_map(&.instructions)
        .find { |inst| inst.is_a?(Adamas::HIR::Call) }
      call.should_not be_nil

      call_name = call.not_nil!.as(Adamas::HIR::Call).method_name
      call_name.should_not contain("Box#value")
      call_name.should_not contain("Bag#value")
    end

    it "prefers module class methods for module-typed receivers" do
      code = <<-CRYSTAL
        module M
          extend self

          def foo : Int32
            1
          end
        end

        class Box
          include M

          def foo : Int32
            2
          end
        end

        def foo(x : M)
          x.foo
        end
      CRYSTAL

      converter = lower_program(code)
      func = converter.module.functions.find { |f| f.name.split("$").first == "foo" }
      func.should_not be_nil

      call = func.not_nil!.blocks.flat_map(&.instructions)
        .find { |inst| inst.is_a?(Adamas::HIR::Call) }
      call.should_not be_nil

      call_name = call.not_nil!.as(Adamas::HIR::Call).method_name
      call_name.should contain("M.foo")
    end

    # TODO: Module-typed receiver resolution needs virtual dispatch enhancements
    pending "prefers includers that match arity for module-typed params" do
      code = <<-CRYSTAL
        module M
        end

        class Box
          include M
          def value(x : Int32) : Int32
            x
          end
        end

        class Bag
          include M
          def value(x : Int32, y : Int32) : Int32
            x + y
          end
        end

        def foo(x : M)
          x.value(1)
        end
      CRYSTAL

      converter = lower_program(code)
      func = converter.module.functions.find { |f| f.name.split("$").first == "foo" }
      func.should_not be_nil

      call = func.not_nil!.blocks.flat_map(&.instructions)
        .find { |inst| inst.is_a?(Adamas::HIR::Call) }
      call.should_not be_nil

      call.not_nil!.as(Adamas::HIR::Call).method_name.should contain("Box#value")
    end

    # TODO: Module-typed receiver resolution needs virtual dispatch enhancements
    pending "prefers includers that match parameter types for module-typed params" do
      code = <<-CRYSTAL
        module M
        end

        class Box
          include M
          def value(x : Int32) : Int32
            x
          end
        end

        class Bag
          include M
          def value(x : String) : Int32
            x.size
          end
        end

        def foo(x : M)
          x.value(1)
        end
      CRYSTAL

      converter = lower_program(code)
      func = converter.module.functions.find { |f| f.name.split("$").first == "foo" }
      func.should_not be_nil

      call = func.not_nil!.blocks.flat_map(&.instructions)
        .find { |inst| inst.is_a?(Adamas::HIR::Call) }
      call.should_not be_nil

      call.not_nil!.as(Adamas::HIR::Call).method_name.should contain("Box#value")
    end
  end

  describe "module accessor mixins" do
    it "generates accessors from included modules for classes" do
      code = <<-CRYSTAL
        module M
          getter foo : Int32
          property bar : Int32
        end

        class Box
          include M
          def initialize(@foo : Int32, @bar : Int32)
          end
        end
      CRYSTAL

      converter = lower_program(code)
      getter = converter.module.functions.find { |f| f.name == "Box#foo" }
      getter.should_not be_nil

      setter = converter.module.functions.find { |f| f.name.split("$").first == "Box#bar=" }
      setter.should_not be_nil

      ivars = converter.class_info["Box"].ivars.map(&.name)
      ivars.should contain("@foo")
      ivars.should contain("@bar")
    end

    it "generates accessors from included modules for structs" do
      code = <<-CRYSTAL
        module M
          getter foo : Int32
        end

        struct Bag
          include M
          def initialize(@foo : Int32)
          end
        end
      CRYSTAL

      converter = lower_program(code)
      getter = converter.module.functions.find { |f| f.name == "Bag#foo" }
      getter.should_not be_nil

      ivars = converter.class_info["Bag"].ivars.map(&.name)
      ivars.should contain("@foo")
    end
  end

  describe "registration-time implicit ivar discovery" do
    it "preserves a class-scope default discovered after an ivar already exists" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class LateDefaultToken
        end

        class ReopenedInlineDefault
          @cache : LateDefaultToken
        end

        class ReopenedInlineDefault
          @cache = LateDefaultToken.new

          def initialize
          end
        end

        ReopenedInlineDefault.new
      CRYSTAL

      cache = converter.class_info["ReopenedInlineDefault"].ivars.find { |ivar| ivar.name == "@cache" }
      cache.should_not be_nil
      cache.not_nil!.default_expr_id.should_not be_nil

      allocator = converter.module.function_by_name("ReopenedInlineDefault.new")
      allocator.should_not be_nil
      calls = allocator.not_nil!.blocks.flat_map(&.instructions)
        .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      calls.count { |call| call.method_name == "LateDefaultToken.new" }.should eq(1)
    end

    it "preserves signed class-scope defaults through allocator lowering" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class InlineDefaultState
          @regular = -7
          @small = -7_i8
          @ratio = -1.5

          def initialize
          end
        end

        InlineDefaultState.new
      CRYSTAL

      class_info = converter.class_info["InlineDefaultState"]
      regular = class_info.ivars.find { |ivar| ivar.name == "@regular" }
      small = class_info.ivars.find { |ivar| ivar.name == "@small" }
      ratio = class_info.ivars.find { |ivar| ivar.name == "@ratio" }
      regular.should_not be_nil
      small.should_not be_nil
      ratio.should_not be_nil
      regular.not_nil!.default_expr_id.should_not be_nil
      small.not_nil!.default_expr_id.should_not be_nil
      ratio.not_nil!.default_expr_id.should_not be_nil
      regular.not_nil!.type.should eq(Adamas::HIR::TypeRef::INT32)
      small.not_nil!.type.should eq(Adamas::HIR::TypeRef::INT8)
      ratio.not_nil!.type.should eq(Adamas::HIR::TypeRef::FLOAT64)

      allocator = converter.module.function_by_name("InlineDefaultState.new")
      allocator.should_not be_nil
      instructions = allocator.not_nil!.blocks.flat_map(&.instructions)
      regular_store = instructions.compact_map { |instruction| instruction.as?(Adamas::HIR::FieldSet) }
        .find { |field| field.field_name == "@regular" }
      small_store = instructions.compact_map { |instruction| instruction.as?(Adamas::HIR::FieldSet) }
        .find { |field| field.field_name == "@small" }
      regular_store.should_not be_nil
      small_store.should_not be_nil
      regular_store.not_nil!.type.should eq(Adamas::HIR::TypeRef::INT32)
      small_store.not_nil!.type.should eq(Adamas::HIR::TypeRef::INT8)
    end

    it "scans ordinary method bodies without reading their parameter storage" do
      code = <<-CRYSTAL
        class BodyAssignedIvar
          def initialize
            @value = 7
          end
        end
      CRYSTAL
      arena, exprs = parse(code)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => code},
      )
      class_node = exprs.compact_map { |id| arena[id].as?(Adamas::Compiler::Frontend::ClassNode) }.first

      converter.register_class(class_node)

      value = converter.class_info["BodyAssignedIvar"].ivars.find { |ivar| ivar.name == "@value" }
      value.should_not be_nil
      value.not_nil!.type.should eq(Adamas::HIR::TypeRef::INT32)
    end

    it "infers an explicit cast before lowering the assigning body" do
      code = <<-CRYSTAL
        class CastAssignedIvar
          def initialize
            @context = nil.as(String?)
          end
        end
      CRYSTAL
      arena, exprs = parse(code)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => code},
      )
      class_node = exprs.compact_map { |id| arena[id].as?(Adamas::Compiler::Frontend::ClassNode) }.first

      converter.register_class(class_node)

      context = converter.class_info["CastAssignedIvar"].ivars.find { |ivar| ivar.name == "@context" }
      context.should_not be_nil
      context.not_nil!.type.should eq(converter.__test_type_ref_for_name("String?"))
    end

    it "keeps a question cast on its HIR target carrier before lowering the body" do
      code = <<-CRYSTAL
        class QuestionCastAssignedIvar
          def initialize(value : Object)
            @context = value.as?(String)
          end
        end
      CRYSTAL
      arena, exprs = parse(code)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => code},
      )
      class_node = exprs.compact_map { |id| arena[id].as?(Adamas::Compiler::Frontend::ClassNode) }.first

      converter.register_class(class_node)

      context = converter.class_info["QuestionCastAssignedIvar"].ivars.find { |ivar| ivar.name == "@context" }
      context.should_not be_nil
      context.not_nil!.type.should eq(Adamas::HIR::TypeRef::STRING)
    end

    it "keeps looking after an assignment whose type is not known at registration" do
      code = <<-CRYSTAL
        class DeferredAssignedIvar
          def initialize(value)
            @value = value
            @value = 7
          end
        end
      CRYSTAL
      arena, exprs = parse(code)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => code},
      )
      class_node = exprs.compact_map { |id| arena[id].as?(Adamas::Compiler::Frontend::ClassNode) }.first

      converter.register_class(class_node)

      value = converter.class_info["DeferredAssignedIvar"].ivars.find { |ivar| ivar.name == "@value" }
      value.should_not be_nil
      value.not_nil!.type.should eq(Adamas::HIR::TypeRef::INT32)
    end

    it "scans every branch of a begin expression before lowering the body" do
      code = <<-CRYSTAL
        class BeginAssignedIvars
          def initialize
            begin
              @body_value = 1
            rescue
              @rescue_value = true
            else
              @else_value = 'e'
            ensure
              @ensure_value = "done"
            end
          end
        end
      CRYSTAL
      arena, exprs = parse(code)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => code},
      )
      class_node = exprs.compact_map { |id| arena[id].as?(Adamas::Compiler::Frontend::ClassNode) }.first

      converter.register_class(class_node)

      ivars = converter.class_info["BeginAssignedIvars"].ivars
      ivars.map(&.name).should contain("@body_value")
      ivars.map(&.name).should contain("@rescue_value")
      ivars.map(&.name).should contain("@else_value")
      ivars.map(&.name).should contain("@ensure_value")
    end

    it "scans elsif branches before lowering the body" do
      code = <<-CRYSTAL
        class ElsifAssignedIvar
          def initialize(flag : Bool)
            if flag
              0
            elsif flag
              @late = 1
            end
          end
        end
      CRYSTAL
      arena, exprs = parse(code)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => code},
      )
      class_node = exprs.compact_map { |id| arena[id].as?(Adamas::Compiler::Frontend::ClassNode) }.first

      converter.register_class(class_node)

      late = converter.class_info["ElsifAssignedIvar"].ivars.find { |ivar| ivar.name == "@late" }
      late.should_not be_nil
      late.not_nil!.type.should eq(Adamas::HIR::TypeRef::INT32)
    end

    it "preserves extern out parameter discovery while scanning method bodies" do
      code = <<-CRYSTAL
        lib RegistrationProbe
          fun fill(value : Int32*) : Int32
        end

        class OutAssignedIvar
          def initialize
            RegistrationProbe.fill(out @value)
          end
        end
      CRYSTAL
      arena, exprs = parse(code)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => code},
      )
      lib_node = exprs.compact_map { |id| arena[id].as?(Adamas::Compiler::Frontend::LibNode) }.first
      class_node = exprs.compact_map { |id| arena[id].as?(Adamas::Compiler::Frontend::ClassNode) }.first

      converter.register_lib(lib_node)
      converter.register_class(class_node)

      value = converter.class_info["OutAssignedIvar"].ivars.find { |ivar| ivar.name == "@value" }
      value.should_not be_nil
      value.not_nil!.type.should eq(Adamas::HIR::TypeRef::INT32)
    end

    it "preserves numeric literal suffixes in array element types" do
      code = <<-CRYSTAL
        class SuffixedArrayAssignedIvar
          def initialize
            @values = [0_u8]
          end
        end
      CRYSTAL
      arena, exprs = parse(code)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => code},
      )
      class_node = exprs.compact_map { |id| arena[id].as?(Adamas::Compiler::Frontend::ClassNode) }.first

      converter.register_class(class_node)

      values = converter.class_info["SuffixedArrayAssignedIvar"].ivars.find { |ivar| ivar.name == "@values" }
      values.should_not be_nil
      descriptor = converter.module.get_type_descriptor(values.not_nil!.type)
      descriptor.should_not be_nil
      descriptor.not_nil!.name.should eq("Array(UInt8)")
    end

    it "normalizes rooted generic constructor types" do
      code = <<-CRYSTAL
        class RootedGenericAssignedIvar
          def initialize
            @values = ::Array(UInt32).new
          end
        end
      CRYSTAL
      arena, exprs = parse(code)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => code},
      )
      class_node = exprs.compact_map { |id| arena[id].as?(Adamas::Compiler::Frontend::ClassNode) }.first

      converter.register_class(class_node)

      values = converter.class_info["RootedGenericAssignedIvar"].ivars.find { |ivar| ivar.name == "@values" }
      values.should_not be_nil
      descriptor = converter.module.get_type_descriptor(values.not_nil!.type)
      descriptor.should_not be_nil
      descriptor.not_nil!.name.should eq("Array(UInt32)")
    end

    it "does not treat rooted runtime calls as generic type names" do
      code = <<-CRYSTAL
        class RootedRuntimeCallAssignedIvar
          def initialize
            @value = ::factory(UInt32).new
          end
        end
      CRYSTAL
      arena, exprs = parse(code)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => code},
      )
      class_node = exprs.compact_map { |id| arena[id].as?(Adamas::Compiler::Frontend::ClassNode) }.first

      converter.register_class(class_node)

      converter.class_info["RootedRuntimeCallAssignedIvar"].ivars.none? { |ivar| ivar.name == "@value" }.should be_true
    end

    it "uses typed method parameters for assigned ivar types" do
      code = <<-CRYSTAL
        class ParameterAssignedIvar
          def initialize(value : String)
            @value = value
          end
        end
      CRYSTAL
      arena, exprs = parse(code)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => code},
      )
      class_node = exprs.compact_map { |id| arena[id].as?(Adamas::Compiler::Frontend::ClassNode) }.first

      converter.register_class(class_node)

      value = converter.class_info["ParameterAssignedIvar"].ivars.find { |ivar| ivar.name == "@value" }
      value.should_not be_nil
      value.not_nil!.type.should eq(Adamas::HIR::TypeRef::STRING)
    end

    it "does not reuse a parameter type after local reassignment" do
      code = <<-CRYSTAL
        class ReassignedParameterIvar
          def initialize(value : String)
            value = 1
            @value = value
          end
        end
      CRYSTAL
      arena, exprs = parse(code)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => code},
      )
      class_node = exprs.compact_map { |id| arena[id].as?(Adamas::Compiler::Frontend::ClassNode) }.first

      converter.register_class(class_node)

      converter.class_info["ReassignedParameterIvar"].ivars.none? { |ivar| ivar.name == "@value" }.should be_true
    end

    it "does not guess parameter refinement inside nested control flow" do
      code = <<-CRYSTAL
        class RefinedParameterIvar
          def initialize(value : String | Int32)
            if value.is_a?(String)
              @value = value
            end
          end
        end
      CRYSTAL
      arena, exprs = parse(code)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => code},
      )
      class_node = exprs.compact_map { |id| arena[id].as?(Adamas::Compiler::Frontend::ClassNode) }.first

      converter.register_class(class_node)

      converter.class_info["RefinedParameterIvar"].ivars.none? { |ivar| ivar.name == "@value" }.should be_true
    end
  end

  describe "generic block return types" do
    it "substitutes block return type params in call return types" do
      code = <<-CRYSTAL
        def map_like(&block : Int32 -> U) : Array(U) forall U
          [] of U
        end

        def foo
          map_like { 1 }
        end
      CRYSTAL

      converter = lower_program(code)
      func = converter.module.functions.find { |f| f.name.starts_with?("foo") }
      func.should_not be_nil

      call = func.not_nil!.blocks.flat_map(&.instructions)
        .find { |inst| inst.is_a?(Adamas::HIR::Call) && inst.as(Adamas::HIR::Call).method_name.includes?("map_like") }
      call.should_not be_nil

      desc = converter.module.get_type_descriptor(call.not_nil!.as(Adamas::HIR::Call).type)
      desc.should_not be_nil
      desc.not_nil!.name.should eq("Array(Int32)")
    end
  end

  describe "typeof in alias targets" do
    it "resolves typeof(self) without local context" do
      code = <<-CRYSTAL
        class Box
          alias SelfType = typeof(self)

          def foo : SelfType
            self
          end
        end
      CRYSTAL

      converter = lower_program(code)
      # Methods with no params get arity suffix
      func = converter.module.functions.find { |f| f.name.starts_with?("Box#foo") }
      func.should_not be_nil

      box_type = converter.class_info["Box"].type_ref
      func.not_nil!.return_type.should eq(box_type)
    end
  end

  describe "typeof in type positions" do
    it "resolves typeof in generic type args using locals" do
      code = <<-CRYSTAL
        class Box(T)
          def initialize(@value : T)
          end
        end

        def foo(x : Int32)
          b = Box(typeof(x)).new(x)
          b
        end
      CRYSTAL

      converter = lower_program(code)
      func = converter.module.functions.find { |item| item.name.starts_with?("foo$") || item.name == "foo" }
      func.should_not be_nil

      box_local = func.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        local = instruction.as?(Adamas::HIR::Local)
        local if local && local.name == "b"
      end.first?
      box_local.should_not be_nil

      box_desc = converter.module.get_type_descriptor(box_local.not_nil!.type)
      box_desc.should_not be_nil
      box_desc.not_nil!.name.should eq("Box(Int32)")
    end

    it "handles nested Enumerable.element_type without parentheses" do
      code = <<-CRYSTAL
        def foo(indexables : Array(Array(Int32)))
          ary = [] of typeof(Enumerable.element_type Enumerable.element_type indexables)
          ary
        end
      CRYSTAL

      converter = lower_program(code)
      func = converter.module.functions.find { |f| f.name.starts_with?("foo$") || f.name == "foo" }
      func.should_not be_nil

      array_lit = func.not_nil!.blocks.flat_map(&.instructions)
        .find { |inst| inst.is_a?(Adamas::HIR::ArrayLiteral) }
      array_lit.should_not be_nil

      element_type = array_lit.not_nil!.as(Adamas::HIR::ArrayLiteral).element_type
      desc = converter.module.get_type_descriptor(element_type)
      if desc
        desc.not_nil!.name.should eq("Int32")
      else
        element_type.should eq(Adamas::HIR::TypeRef::INT32)
      end
    end
  end

  describe "generic specialization return inference" do
    it "infers return types for specialized generic methods" do
      code = <<-CRYSTAL
        class Box(T)
          def initialize(@value : T)
          end

          def value
            @value
          end
        end

        def use
          Box(Int32).new(1).value
        end
      CRYSTAL

      converter = lower_program(code)
      func = converter.module.functions.find { |f| f.name == "Box(Int32)#value" }
      func.should_not be_nil
      func.not_nil!.return_type.should eq(Adamas::HIR::TypeRef::INT32)
    end
  end

  describe "macro if in module bodies" do
    it "registers module methods from active flag branches" do
      code = <<-CRYSTAL
        module M
          {% if flag?(:darwin) %}
            def self.foo
              1
            end
          {% end %}
        end

        def use
          M.foo
        end
      CRYSTAL

      converter = lower_program_with_sources(code)
      converter.module.has_function?("M.foo").should be_true
    end

    it "keeps yield overloads from a no-tracing branch with nested modules" do
      code = <<-CRYSTAL
        module Crystal
          module Tracing
            enum Section
              GC
            end
          end

          {% if flag?(:tracing) %}
            module Tracing
              def self.enabled?(section : Section)
                false
              end
            end

            def self.trace(section : Tracing::Section, operation : String, time : UInt64? = nil, **metadata, &)
              yield
            end
          {% else %}
            module Tracing
              def self.enabled?(section : Section)
                false
              end
            end

            def self.trace(section : Tracing::Section, operation : String, time : UInt64? = nil, **metadata, &)
              yield
            end
          {% end %}
        end

        Crystal.trace(:gc, "malloc_atomic", size: 8_u64, atomic: 1) do
          7
        end
      CRYSTAL

      converter = lower_program_with_sources(code)
      converter.__test_function_def_names("Crystal.trace").should_not be_empty
      converter.__test_function_def_names("Crystal::Tracing.enabled?").should_not be_empty
      main = converter.module.function_by_name("__adamas_main").not_nil!
      main_text = hir_text(main)
      main_text.should_not contain("Crystal.trace")
      main_text.should_not contain("with_block")
      main_text.should contain("literal 7")
    end

    it "preserves the return value of a conditional module method" do
      converter = lower_program_with_sources(<<-CRYSTAL)
        module M
          {% if flag?(:tracing) %}
            def self.foo : Int32
              1
            end
          {% else %}
            def self.foo : Int32
              2
            end
          {% end %}
        end

        M.foo
      CRYSTAL

      converter.__test_lower_function_if_needed("M.foo")
      function = converter.module.functions.find { |func| func.name.starts_with?("M.foo") }.not_nil!
      text = hir_text(function)
      text.should contain("literal 2")
      text.should_not contain("literal nil : Nil")
    end

    it "registers extend self methods from macro bodies" do
      code = <<-CRYSTAL
        module M
          macro add
            extend self

            def foo
              1
            end
          end

          add
        end

        def use
          M.foo
        end
      CRYSTAL

      converter = lower_program_with_sources(code)
      converter.module.has_function?("M.foo").should be_true
    end
  end

  describe "macro expansion in HIR" do
    it "expands control branches before interpolation in mixed macro literals" do
      converter = lower_program_with_sources(<<-CRYSTAL)
        macro define_mixed_value
          {% if flag?(:tracing) %}
            def mixed_macro_value : Int32
              {{ 1 + 2 }}
            end
          {% else %}
            def mixed_macro_value : Int32
              {{ 3 + 4 }}
            end
          {% end %}
        end

        define_mixed_value()
        mixed_macro_value()
      CRYSTAL

      converter.__test_lower_function_if_needed("mixed_macro_value")
      function = converter.module.functions.find do |func|
        func.name == "mixed_macro_value" || func.name.starts_with?("mixed_macro_value$")
      end
      function.should_not be_nil
      text = hir_text(function.not_nil!)
      text.should contain("literal 7")
      text.should_not contain("literal 3")
    end

    it "binds named args with external names" do
      code = <<-CRYSTAL
        macro delegate(*methods, to object)
          {% for method in methods %}
            def {{method.id}}
              {{object.id}}
            end
          {% end %}
        end

        class Wrapper
          def initialize(@value : Int32)
          end

          delegate size, to: @value
        end
      CRYSTAL

      converter = lower_program_with_sources(code)
      converter.module.has_function?("Wrapper#size").should be_true
    end

    it "expands record-style macros with assign/type declarations" do
      code = <<-CRYSTAL
        macro getter(name)
          def {{name.id}}
            @{{name.id}}
          end
        end

        macro record(__name name, *properties, **kwargs)
          struct {{name.id}}
            {% for property in properties %}
              {% if property.is_a?(Assign) %}
                getter {{property.target.id}}
              {% elsif property.is_a?(TypeDeclaration) %}
                getter {{property}}
              {% else %}
                getter :{{property.id}}
              {% end %}
            {% end %}

            def initialize({{
                             properties.map do |field|
                               "@\#{field.id}".id
                             end.splat
                           }})
            end

            def copy_with({{
                            properties.map do |property|
                              if property.is_a?(Assign)
                                "\#{property.target.id} _\#{property.target.id} = @\#{property.target.id}".id
                              elsif property.is_a?(TypeDeclaration)
                                "\#{property.var.id} _\#{property.var.id} = @\#{property.var.id}".id
                              else
                                "\#{property.id} _\#{property.id} = @\#{property.id}".id
                              end
                            end.splat
                          }})
              self.class.new({{
                               properties.map do |property|
                                if property.is_a?(Assign)
                                  "_\#{property.target.id}".id
                                elsif property.is_a?(TypeDeclaration)
                                  "_\#{property.var.id}".id
                                else
                                  "_\#{property.id}".id
                                end
                               end.splat
                             }})
            end

            def clone
              self.class.new({{
                               properties.map do |property|
                                if property.is_a?(Assign)
                                  "@\#{property.target.id}.clone".id
                                elsif property.is_a?(TypeDeclaration)
                                  "@\#{property.var.id}.clone".id
                                else
                                  "@\#{property.id}.clone".id
                                end
                               end.splat
                             }})
            end
          end
        end

        record Point, x : Int32, y = 2
      CRYSTAL

      converter = lower_program_with_sources(code)
      converter.module.has_function?("Point#x").should be_true
      converter.module.has_function?("Point#y").should be_true
      initialize_name = converter.__test_function_def_names("Point#initialize").first?
      initialize_name.should_not be_nil
      converter.__test_function_param_default_presence(initialize_name.not_nil!).should eq([false, true])
      converter.__test_initializer_params("Point").should eq([{"x", "Int32"}, {"y", "Int32"}])
      point_ivar_names = converter.class_info["Point"].ivars.map(&.name)
      point_ivar_names.should contain("@x")
      point_ivar_names.should contain("@y")
      copy_with = converter.module.functions.find { |func| func.name.starts_with?("Point#copy_with") }
      copy_with.should_not be_nil
      if func = copy_with
        param_names = func.params.map(&.name)
        param_names.should contain("_x")
        param_names.should contain("_y")
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # BLOCK STRUCTURE TESTS
  # ═══════════════════════════════════════════════════════════════════════════

  describe "block structure" do
    it "creates entry block" do
      func = lower_function("def foo; 1; end")

      func.entry_block.should eq(0_u32)
      func.blocks.size.should be >= 1
    end

    it "terminates all blocks" do
      func = lower_function("def foo(x : Bool); if x; 1; else; 2; end; end")

      func.blocks.each do |block|
        block.terminator.should_not be_a(Adamas::HIR::Unreachable)
      end
    end

    it "creates correct CFG for if" do
      func = lower_function("def foo(x : Bool); if x; 1; else; 2; end; end")

      # Should have: entry -> branch -> then/else -> merge
      func.blocks.size.should be >= 4

      # Entry should end with branch
      entry = func.get_block(func.entry_block)
      entry.terminator.should be_a(Adamas::HIR::Branch)
    end

    it "creates correct CFG for while" do
      func = lower_function("def foo; while true; 1; end; end")

      # Entry -> jump -> cond -> branch -> body/exit
      # body -> jump back to cond
      func.blocks.size.should be >= 3

      # Should have at least one Jump back (loop)
      jumps = func.blocks.count { |b| b.terminator.is_a?(Adamas::HIR::Jump) }
      jumps.should be >= 1
    end

    it "phi nodes have correct incoming edges" do
      func = lower_function("def foo(x : Bool); if x; 1; else; 2; end; end")

      phi = func.blocks.flat_map(&.instructions).find { |i| i.is_a?(Adamas::HIR::Phi) }
      phi.should_not be_nil

      phi_node = phi.not_nil!.as(Adamas::HIR::Phi)
      phi_node.incoming.size.should eq(2)  # then and else branches
    end

    it "keeps typed-pointer variants distinct and pointer/header merges tagged" do
      arena, _ = parse("def placeholder; 1; end")
      converter = Adamas::HIR::AstToHir.new(arena)
      ptr_i32 = converter.__test_type_ref_for_name("Pointer(Int32)")
      ptr_u8 = converter.__test_type_ref_for_name("Pointer(UInt8)")
      header = converter.__test_type_ref_for_name("String")

      typed_union = converter.__test_union_type_for_values(ptr_i32, ptr_u8)
      converter.__test_get_type_name_from_ref(typed_union).should eq("Pointer(Int32) | Pointer(UInt8)")

      mixed_union = converter.__test_union_type_for_values(Adamas::HIR::TypeRef::POINTER, header)
      converter.__test_get_type_name_from_ref(mixed_union).should eq("Pointer | String")
    end

    it "normalizes a repeated return-type set in one batch without losing variants" do
      arena, _ = parse("def placeholder; 1; end")
      converter = Adamas::HIR::AstToHir.new(arena)
      unique_types = Array(Adamas::HIR::TypeRef).new(200) do |index|
        converter.__test_type_ref_for_name("IncluderReturn#{index}")
      end
      repeated_types = [] of Adamas::HIR::TypeRef
      4.times { unique_types.each { |type_ref| repeated_types << type_ref } }

      merged = converter.__test_union_type_for_value_set(repeated_types)
      merged.should_not be_nil
      variants = converter.__test_get_type_name_from_ref(merged.not_nil!)
        .split('|')
        .map(&.strip)

      variants.size.should eq(unique_types.size)
      variants.to_set.size.should eq(unique_types.size)
      variants.should contain("IncluderReturn0")
      variants.should contain("IncluderReturn199")
    end

    it "preserves a sole existing union and flattens it only when merging other returns" do
      arena, _ = parse("def placeholder; 1; end")
      converter = Adamas::HIR::AstToHir.new(arena)
      existing = converter.__test_union_type_for_values(
        Adamas::HIR::TypeRef::INT32,
        Adamas::HIR::TypeRef::UINT8,
      )

      converter.__test_union_type_for_value_set([existing, existing]).should eq(existing)

      merged = converter.__test_union_type_for_value_set([
        existing,
        Adamas::HIR::TypeRef::STRING,
        Adamas::HIR::TypeRef::INT32,
        Adamas::HIR::TypeRef::NIL,
      ])
      merged.should_not be_nil
      variants = converter.__test_get_type_name_from_ref(merged.not_nil!)
        .split('|')
        .map(&.strip)
        .to_set

      variants.should eq(Set{"Nil", "Int32", "String", "UInt8"})
    end

    it "preserves the concrete pointee type produced by pointerof" do
      converter = lower_program(<<-CRYSTAL)
        module LibC
          struct Timespec
            def initialize(@seconds : Int64)
            end
          end
        end

        def timespec_pointer
          ts = uninitialized LibC::Timespec
          pointerof(ts)
        end
      CRYSTAL

      func = converter.module.functions.find { |candidate| candidate.name.starts_with?("timespec_pointer") }
      func.should_not be_nil
      address = func.not_nil!.blocks.flat_map(&.instructions)
        .compact_map { |inst| inst.as?(Adamas::HIR::AddressOf) }
        .last

      descriptor = converter.module.get_type_descriptor(address.type)
      descriptor.should_not be_nil
      descriptor.not_nil!.kind.should eq(Adamas::HIR::TypeKind::Pointer)
      descriptor.not_nil!.name.should eq("Pointer(LibC::Timespec)")
    end

    it "preserves the concrete pointee type of Pointer(T).null in a nested namespace" do
      converter = lower_program(<<-CRYSTAL)
        module LibC
          struct Timespec
            def initialize(@seconds : Int64)
            end
          end
        end

        module Crystal
          module System
            class Kqueue
              def null_timeout
                Pointer(LibC::Timespec).null
              end
            end
          end
        end
      CRYSTAL

      func = converter.module.functions.find { |candidate| candidate.name.includes?("Kqueue#null_timeout") }
      func.should_not be_nil
      cast = func.not_nil!.blocks.flat_map(&.instructions)
        .compact_map { |inst| inst.as?(Adamas::HIR::Cast) }
        .last

      descriptor = converter.module.get_type_descriptor(cast.type)
      descriptor.should_not be_nil
      descriptor.not_nil!.kind.should eq(Adamas::HIR::TypeKind::Pointer)
      descriptor.not_nil!.name.should eq("Pointer(LibC::Timespec)")
    end

    it "merges pointerof(T) with Pointer(T).null without synthesizing a union" do
      converter = lower_program(<<-CRYSTAL)
        module LibC
          struct Timespec
            def initialize(@seconds : Int64)
            end
          end
        end

        module Crystal
          module System
            class Kqueue
              def timeout_pointer(has_timeout : Bool)
                if has_timeout
                  ts = uninitialized LibC::Timespec
                  tsp = pointerof(ts)
                else
                  tsp = Pointer(LibC::Timespec).null
                end
                tsp
              end
            end
          end
        end
      CRYSTAL

      func = converter.module.functions.find { |candidate| candidate.name.includes?("Kqueue#timeout_pointer") }
      func.should_not be_nil
      instructions = func.not_nil!.blocks.flat_map(&.instructions)
      pointer_name = "Pointer(LibC::Timespec)"
      pointer_phi = instructions.compact_map { |inst| inst.as?(Adamas::HIR::Phi) }.find do |phi|
        converter.__test_get_type_name_from_ref(phi.type) == pointer_name
      end

      pointer_phi.should_not be_nil
      pointer_phi.not_nil!.incoming.size.should eq(2)
      instructions.compact_map { |inst| inst.as?(Adamas::HIR::UnionWrap) }
        .none? { |wrap| converter.__test_get_type_name_from_ref(wrap.type).includes?("Pointer") }
        .should be_true
      converter.__test_get_type_name_from_ref(func.not_nil!.return_type).should eq(pointer_name)
    end

    it "keeps inherited parameter annotations in the defining owner's namespace" do
      converter = lower_program(<<-CRYSTAL)
        module LexicalPointerOwner
          module Event
          end

          abstract class Polling
            struct Event
            end

            def add_timer(event : Event*) : Nil
              consume(event)
            end

            private def consume(event : Event*) : Nil
              nil
            end
          end

          class Kqueue < Polling
          end
        end
      CRYSTAL

      target_name =
        "LexicalPointerOwner::Kqueue#add_timer$Pointer(LexicalPointerOwner::Polling::Event)"
      pointer_type =
        converter.__test_type_ref_for_name("Pointer(LexicalPointerOwner::Polling::Event)")
      source_name =
        "LexicalPointerOwner::Polling#add_timer$Pointer(LexicalPointerOwner::Polling::Event)"
      converter.__test_lower_inherited_method_specialization(
        source_name,
        "LexicalPointerOwner::Kqueue",
        target_name,
        [pointer_type],
      )
      target = converter.module.function_by_name(target_name)
      target.should_not be_nil

      pointer_name = converter.__test_get_type_name_from_ref(target.not_nil!.params.last.type)
      pointer_name.should eq("Pointer(LexicalPointerOwner::Polling::Event)")

      calls = target.not_nil!.blocks
        .flat_map(&.instructions)
        .compact_map(&.as?(Adamas::HIR::Call))
        .map(&.method_name)
      calls.any? do |name|
        name.starts_with?(
          "LexicalPointerOwner::Polling#consume$Pointer(LexicalPointerOwner::Polling::Event)"
        )
      end.should be_true
      calls.none? do |name|
        name.includes?("Pointer(LexicalPointerOwner::Event)")
      end.should be_true
    end

    it "narrows a nilable index before specializing mixed-width slice arguments" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class NarrowedIndexBuffer
          def size : Int32
            8
          end

          def index(value : Int32, offset) : Nil | Int32 | UInt32
            if value < 0
              nil
            elsif offset > 0
              offset
            else
              4
            end
          end

          def [](start : Int, count : Int) : Int32
            count
          end
        end

        class NarrowedIndexDecoder
          def initialize
            @buffer = NarrowedIndexBuffer.new
          end

          def decode(offset)
            if offset < @buffer.size
              index = @buffer.index(0, offset: offset)
              return @buffer[offset, index - offset] if index
            end
            0
          end
        end

        NarrowedIndexDecoder.new.decode(1_u32)
      CRYSTAL
      converter.flush_pending_functions

      target = converter.module.function_by_name("NarrowedIndexDecoder#decode$UInt32")
      target.should_not be_nil
      calls = target.not_nil!.blocks
        .flat_map(&.instructions)
        .compact_map(&.as?(Adamas::HIR::Call))
        .select { |call| call.method_name.starts_with?("NarrowedIndexBuffer#[]$") }
      calls.size.should eq(1)
      calls.first.method_name.should_not contain("Nil")
      lowered_target = converter.module.function_by_name(calls.first.method_name)
      lowered_target.should_not be_nil
      lowered_target.not_nil!.blocks.any? { |block| !block.instructions.empty? }.should be_true
      argument_types = calls.first.args.map do |arg|
        value = target.not_nil!.params.find { |param| param.id == arg } ||
                target.not_nil!.blocks.flat_map(&.instructions).find { |inst| inst.id == arg }
        value ? converter.__test_get_type_name_from_ref(value.type) : "missing"
      end
      argument_types.first.should eq("UInt32")
      argument_types.last.should_not contain("Nil")
    end

    it "narrows mixed primitive unions on the truthy side of ||" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class CoalescedIndexBuffer
          def index(value : Int32, offset) : Nil | Int32 | UInt32
            if value < 0
              nil
            elsif offset > 0
              offset
            else
              4
            end
          end

          def [](start : Int, count : Int) : Int32
            count
          end
        end

        class CoalescedIndexDecoder
          def initialize
            @buffer = CoalescedIndexBuffer.new
          end

          def coalesce(offset)
            index = @buffer.index(0, offset: offset)
            @buffer[index || 0, 1]
          end
        end

        CoalescedIndexDecoder.new.coalesce(1_u32)
      CRYSTAL
      converter.flush_pending_functions

      target = converter.module.function_by_name("CoalescedIndexDecoder#coalesce$UInt32")
      target.should_not be_nil
      wraps = target.not_nil!.blocks.flat_map(&.instructions)
        .compact_map(&.as?(Adamas::HIR::UnionWrap))
      wraps.any? do |wrap|
        wrap.variant_type_id == -2 &&
          converter.__test_get_type_name_from_ref(wrap.type) == "Int32 | UInt32"
      end.should be_true

      calls = target.not_nil!.blocks
        .flat_map(&.instructions)
        .compact_map(&.as?(Adamas::HIR::Call))
        .select { |call| call.method_name.starts_with?("CoalescedIndexBuffer#[]$") }
      calls.size.should eq(1)
      calls.first.method_name.should_not contain("Nil")
      converter.module.function_by_name(calls.first.method_name).should_not be_nil
      argument_types = calls.first.args.map do |arg|
        value = target.not_nil!.params.find { |param| param.id == arg } ||
                target.not_nil!.blocks.flat_map(&.instructions).find { |inst| inst.id == arg }
        value ? converter.__test_get_type_name_from_ref(value.type) : "missing"
      end
      argument_types.none? { |type_name| type_name.includes?("Nil") }.should be_true
    end

    it "does not lower a truthy-only call for a Nil block specialization" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class NilBlockBranchProbe
          private def consume(value) : Int32
            value.to_i
          end

          private def dispatch(value, &)
            if value
              consume(value)
            elsif yield
              1
            else
              0
            end
          end

          def warm : Int32
            dispatch(1_u8) { false }
          end

          def nil_path : Int32
            dispatch(nil) { true }
          end
        end

        probe = NilBlockBranchProbe.new
        probe.warm
        probe.nil_path
      CRYSTAL
      converter.flush_pending_functions

      nil_path = converter.module.functions.find do |function|
        function.name.starts_with?("NilBlockBranchProbe#nil_path")
      end
      nil_path.should_not be_nil
      calls = nil_path.not_nil!.blocks.flat_map(&.instructions)
        .compact_map(&.as?(Adamas::HIR::Call))
      calls.none? do |call|
        call.method_name.includes?("consume") || call.method_name.starts_with?("Nil#to_i")
      end.should be_true
    end

    it "does not lower includes? for a statically Nil optional parameter in an OR chain" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class NilIncludesGuardProbe
          private def maybe_text(flag : Bool) : String?
            flag ? "candidate" : nil
          end

          private def match_texts?(
            token : String,
            text1 : String? = nil,
            text2 : String? = nil,
            text3 : String? = nil,
            text4 : String? = nil,
          ) : Bool
            (!text1.nil? && text1.includes?(token)) ||
              (!text2.nil? && text2.includes?(token)) ||
              (!text3.nil? && text3.includes?(token)) ||
              (!text4.nil? && text4.includes?(token))
          end

          def run(flag : Bool) : Bool
            match_texts?("needle", "first", nil, maybe_text(flag), maybe_text(!flag))
          end
        end

        NilIncludesGuardProbe.new.run(true)
      CRYSTAL
      converter.flush_pending_functions

      targets = converter.module.functions.select do |function|
        function.name.starts_with?("NilIncludesGuardProbe#match_texts?$") &&
          function.name.includes?("_Nil_")
      end
      targets.empty?.should be_false
      instructions = targets.flat_map(&.blocks).flat_map(&.instructions)
      call_names = instructions.compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call).try(&.method_name)
      end
      call_names.none? { |name| name.starts_with?("Nil#includes?$") }.should be_true
      extern_names = instructions.compact_map do |instruction|
        instruction.as?(Adamas::HIR::ExternCall).try(&.extern_name)
      end
      extern_names.should contain("__adamas_string_includes_string")
    end
  end

  describe "block parameter types" do
    it "applies block param types from callee signature" do
      code = <<-CRYSTAL
        def consume(& : Pointer(Int32) ->)
        end

        def foo
          consume do |ptr|
            ptr
          end
        end
      CRYSTAL

      converter = lower_program(code)
      func = converter.module.functions.find { |f| f.name.starts_with?("foo$") || f.name == "foo" }
      func.should_not be_nil

      params = func.not_nil!.blocks.flat_map(&.instructions)
        .select { |inst| inst.is_a?(Adamas::HIR::Parameter) }
      ptr_param = params.find { |inst| inst.as(Adamas::HIR::Parameter).name == "ptr" }
      ptr_param.should_not be_nil

      param_type = ptr_param.not_nil!.as(Adamas::HIR::Parameter).type
      desc = converter.module.get_type_descriptor(param_type)
      desc.should_not be_nil
      desc.not_nil!.name.should eq("Pointer(Int32)")
    end

    it "substitutes generic block param types from receiver" do
      code = <<-CRYSTAL
        class Box(T)
          def initialize(@value : T)
          end

          def consume(& : T ->)
          end
        end

        def foo
          Box(Int32).new(1).consume do |value|
            value
          end
        end
      CRYSTAL

      converter = lower_program(code)
      func = converter.module.functions.find { |f| f.name.starts_with?("foo$") || f.name == "foo" }
      func.should_not be_nil

      params = func.not_nil!.blocks.flat_map(&.instructions)
        .select { |inst| inst.is_a?(Adamas::HIR::Parameter) }
      value_param = params.find { |inst| inst.as(Adamas::HIR::Parameter).name == "value" }
      value_param.should_not be_nil

      param_type = value_param.not_nil!.as(Adamas::HIR::Parameter).type
      desc = converter.module.get_type_descriptor(param_type)
      if desc
        desc.not_nil!.name.should eq("Int32")
      else
        param_type.should eq(Adamas::HIR::TypeRef::INT32)
      end
    end

    it "preserves a pointer element type through transitive generic yields" do
      converter = lower_program_with_main(<<-CRYSTAL)
        module YieldNS
          struct Descriptor
            def owned_by?(owner) : Bool
              true
            end
          end

          class Arena(T, N)
            struct Index
              getter index

              def initialize(@index : Int32)
              end
            end

            struct Entry(T)
              def pointer : Pointer(T)
                Pointer(T).null
              end
            end

            def get?(index : Index, &) : Bool
              at?(index) do |entry|
                yield entry.value.pointer
                return true
              end
              false
            end

            private def at?(index : Index, &) : Nil
              return unless entry = at?(index.index)
              yield entry
            end

            private def at?(index : Int32) : Pointer(Entry(T))?
              Pointer(Entry(T)).null
            end
          end

          class Caller(T)
            def run(arena : YieldNS::Arena(YieldNS::Descriptor, Int32)) : Bool
              relay(arena) do |pointer|
                pointer.value.owned_by?(self)
              end
            end

            private def relay(arena, &)
              index = YieldNS::Arena::Index.new(0)
              arena.get?(index) do |pointer|
                yield pointer
              end
            end
          end
        end

        YieldNS::Caller(UInt8).new.run(YieldNS::Arena(YieldNS::Descriptor, Int32).new)
      CRYSTAL

      target_name = "YieldNS::Caller(UInt8)#run$YieldNS::Arena(YieldNS::Descriptor, Int32)"
      converter.__test_lower_function_if_needed(target_name)
      target = converter.module.function_by_name(target_name)
      target.should_not be_nil

      producer_name =
        "YieldNS::Arena(YieldNS::Descriptor, Int32)#at?$YieldNS::Arena::Index_block"
      converter.__test_lower_function_if_needed(producer_name)
      producer = converter.module.function_by_name(producer_name)
      producer.should_not be_nil
      producer_values =
        producer.not_nil!.params + producer.not_nil!.blocks.flat_map(&.instructions)
      yielded = producer.not_nil!.blocks
        .flat_map(&.instructions)
        .compact_map(&.as?(Adamas::HIR::Yield))
        .first?
      yielded.should_not be_nil
      yielded_arg = yielded.not_nil!.args.first?
      yielded_arg.should_not be_nil
      yielded_value = producer_values.find { |value| value.id == yielded_arg }
      yielded_value.should_not be_nil
      converter.__test_get_type_name_from_ref(yielded_value.not_nil!.type).should eq(
        "Pointer(YieldNS::Arena::Entry(YieldNS::Descriptor))"
      )

      calls = target.not_nil!.blocks
        .flat_map(&.instructions)
        .compact_map(&.as?(Adamas::HIR::Call))
        .map(&.method_name)
      calls.any? { |name| name.starts_with?("YieldNS::Descriptor#owned_by?") }.should be_true
      calls.none? { |name| name.starts_with?("UInt8#owned_by?") }.should be_true
    end

    it "preserves the concrete element type through an unannotated generic buffer getter" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class YieldBuffer(T)
          protected getter buffer

          def initialize
            @buffer = Pointer(T).null
          end

          def each(& : T ->) : Nil
            YieldBuffer.half_slices(self) do |slice|
              slice.each do |element|
                yield element
              end
            end
          end

          def self.half_slices(buffer : ::YieldBuffer, &)
            yield Slice(typeof(buffer.buffer.value)).new(buffer.buffer, 0)
          end
        end

        YieldBuffer(Int32).new.each { |value| value }
      CRYSTAL

      converter.__test_block_param_types_for_call(
        "YieldBuffer.half_slices",
        "YieldBuffer(Int32).half_slices$YieldBuffer(Int32)_block",
        "YieldBuffer(Int32)",
        ["YieldBuffer(Int32)"],
      ).should eq(["Slice(Int32)"])

      converter.__test_block_param_types_for_call_in_context(
        "YieldBuffer.half_slices",
        "YieldBuffer(Int32).half_slices$YieldBuffer(Int32)_block",
        "YieldBuffer(Int32)",
        {"T" => "Int32"},
        ["YieldBuffer(Int32)"],
      ).should eq(["Slice(Int32)"])
    end

    it "invalidates stale yield-expression types when entering a block contract scope" do
      converter = lower_program_with_main(<<-CRYSTAL)
        module YieldCacheNS
          struct Descriptor
          end

          class Arena
            struct Index
              def initialize(@index : Int32)
              end
            end

            struct Entry
              def pointer : Pointer(Descriptor)
                Pointer(Descriptor).null
              end
            end

            def get?(index : Index, &) : Bool
              at?(index) do |entry|
                yield entry.value.pointer
                return true
              end
              false
            end

            private def at?(index : Index, &) : Nil
              return unless entry = at?(index.index)
              yield entry
            end

            private def at?(index : Int32) : Pointer(Entry)?
              Pointer(Entry).null
            end
          end
        end

        arena = YieldCacheNS::Arena.new
        arena.get?(YieldCacheNS::Arena::Index.new(0)) { |pointer| pointer }
      CRYSTAL

      receiver_name = "YieldCacheNS::Arena"
      function_name = "#{receiver_name}#get?"
      converter.__test_block_param_types_after_stale_yield_cache(
        function_name,
        receiver_name,
        ["YieldCacheNS::Arena::Index"],
      ).should eq(["Pointer(YieldCacheNS::Descriptor)"])
    end

    it "preserves receiver generic bindings in explicit transitive yield annotations" do
      converter = lower_program_with_main(<<-CRYSTAL)
        module YieldExplicitNS
          struct Descriptor
            def owned_by?(owner) : Bool
              true
            end
          end

          class Arena(T, N)
            struct Index
              def initialize(@index : Int32)
              end
            end

            struct Entry(T)
              def pointer : Pointer(T)
                Pointer(T).null
              end
            end

            def allocate_at?(index : Int32, &) : Index?
              entry = at(Index.new(index))
              yield entry.value.pointer, Index.new(index)
              nil
            end

            private def at(index : Index) : Pointer(Entry(T))
              Pointer(Entry(T)).null
            end
          end

          class Caller(T)
            def run(arena : YieldExplicitNS::Arena(YieldExplicitNS::Descriptor, Int32)) : Bool
              arena.allocate_at?(0) do |pointer, index|
                pointer.value.owned_by?(self)
              end
              true
            end
          end
        end

        YieldExplicitNS::Caller(UInt8).new.run(
          YieldExplicitNS::Arena(YieldExplicitNS::Descriptor, Int32).new
        )
      CRYSTAL

      target_name =
        "YieldExplicitNS::Caller(UInt8)#run$YieldExplicitNS::Arena(YieldExplicitNS::Descriptor, Int32)"
      converter.__test_lower_function_if_needed(target_name)
      target = converter.module.function_by_name(target_name)
      target.should_not be_nil

      calls = target.not_nil!.blocks
        .flat_map(&.instructions)
        .compact_map(&.as?(Adamas::HIR::Call))
        .map(&.method_name)
      calls.any? { |name| name.starts_with?("YieldExplicitNS::Descriptor#owned_by?") }.should be_true
      calls.none? { |name| name.starts_with?("UInt8#owned_by?") }.should be_true
    end

    it "fails closed on ambiguous generic-template return annotations" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class GenericConflict(T)
          def probe : Int32
            1
          end
        end

        class GenericConflict(T)
          def probe : String
            "conflict"
          end
        end

        GenericConflict(Int32).new
      CRYSTAL

      converter.__test_resolve_generic_return_type(
        "GenericConflict(Int32)",
        "probe",
        0,
      ).should be_nil
    end

    it "lowers enum literal to_i/value without a method call" do
      code = <<-CRYSTAL
        enum DayOfWeek
          Monday
          Wednesday = 3
        end

        def foo
          DayOfWeek::Wednesday.to_i
        end

        def bar
          DayOfWeek::Wednesday.value
        end
      CRYSTAL

      converter = lower_program(code)
      foo = converter.module.functions.find { |f| f.name.split("$").first == "foo" }
      bar = converter.module.functions.find { |f| f.name.split("$").first == "bar" }

      foo.should_not be_nil
      bar.should_not be_nil

      foo_calls = foo.not_nil!.blocks.flat_map(&.instructions)
        .select { |inst| inst.is_a?(Adamas::HIR::Call) }
        .map { |inst| inst.as(Adamas::HIR::Call).method_name }
      bar_calls = bar.not_nil!.blocks.flat_map(&.instructions)
        .select { |inst| inst.is_a?(Adamas::HIR::Call) }
        .map { |inst| inst.as(Adamas::HIR::Call).method_name }

      foo_calls.any? { |name| name.includes?("to_i") }.should be_false
      bar_calls.any? { |name| name.includes?("value") }.should be_false

      foo_literals = foo.not_nil!.blocks.flat_map(&.instructions)
        .select { |inst| inst.is_a?(Adamas::HIR::Literal) }
        .map { |inst| inst.as(Adamas::HIR::Literal).value }

      foo_literals.includes?(3_i64).should be_true
    end
  end

  describe "pointer overload mangling" do
    it "distinguishes pointer element types in overloads" do
      code = <<-CRYSTAL
        struct Pointer(T)
        end

        def foo(x : Pointer(Int32))
          1
        end

        def foo(x : Pointer(Float64))
          2
        end
      CRYSTAL

      converter = lower_program(code)
      names = converter.module.functions.map(&.name)
      names.should contain("foo$Pointer(Int32)")
      names.should contain("foo$Pointer(Float64)")
    end
  end

  describe "generic arg splitting" do
    it "does not treat braced proc type args as a proc continuation" do
      arena, _exprs = parse("1")
      converter = Adamas::HIR::AstToHir.new(arena)

      converter.__test_split_generic_type_args("String, {String, _} ->")
        .should eq(["String", "{String, _} ->"])
    end
  end

  describe "generic typed-pointer ivars" do
    it "refreshes source-backed ivar annotations after empty initialize storage" do
      converter = lower_source_backed_program_with_empty_initialize_params(<<-CRYSTAL)
        module Adamas
          module Compiler
            module Semantic
              class Program
              end

              class SymbolTable
              end

              class MacroExpander
                def initialize(
                  @program : Program,
                  @arena : Frontend::ArenaLike,
                  flags : Set(String)? = nil,
                  *,
                  symbol_table : SymbolTable? = nil,
                  recovery_mode : Bool = false,
                  source_provider : Proc(ExprId, String?)? = nil,
                  macro_source : String? = ")" # A `)` in a string/comment must not close the signature.
                  macro_source_path : String? = nil,
                  source_sink : Proc(String, Nil)? = nil
                )
                  # This deliberately creates an earlier stale ivar type. The
                  # source-backed parameter annotation must remain authoritative.
                  @arena = "stale"
                end

                def evaluate_macro_body(id : Frontend::ExprId) : Frontend::Node
                  @arena[id]
                end
              end
            end

            module Frontend
              class Node
              end

              struct ExprId
              end

              class AstArena
                def [](id : ExprId) : Node
                  Node.new
                end
              end

              class VirtualArena
                def [](id : ExprId) : Node
                  Node.new
                end
              end

              class PageArena
                def [](id : ExprId) : Node
                  Node.new
                end
              end

              alias ArenaLike = AstArena | VirtualArena | PageArena
            end
          end
        end

        Adamas::Compiler::Semantic::MacroExpander.new(
          Adamas::Compiler::Semantic::Program.new,
          Adamas::Compiler::Frontend::AstArena.new
        ).evaluate_macro_body(Adamas::Compiler::Frontend::ExprId.new)
      CRYSTAL
      converter.fixup_inherited_ivars

      owner_name = "Adamas::Compiler::Semantic::MacroExpander"
      class_info = converter.class_info[owner_name]
      program_ivar = class_info.ivars.find { |ivar| ivar.name == "@program" }
      program_ivar.should_not be_nil
      program_ivar.not_nil!.type.should_not eq(Adamas::HIR::TypeRef::VOID)
      arena_ivar = class_info.ivars.find { |ivar| ivar.name == "@arena" }
      arena_ivar.should_not be_nil
      arena_ivar.not_nil!.type.should_not eq(Adamas::HIR::TypeRef::STRING)
      arena_type = converter.module.get_type_descriptor(arena_ivar.not_nil!.type)
      arena_type.should_not be_nil
      arena_type.not_nil!.kind.should eq(Adamas::HIR::TypeKind::Union)
      arena_type.not_nil!.name.should eq(
        "Adamas::Compiler::Frontend::AstArena | Adamas::Compiler::Frontend::PageArena | Adamas::Compiler::Frontend::VirtualArena"
      )

      evaluate = converter.module.functions.find { |func| func.name.includes?("MacroExpander#evaluate_macro_body") }
      evaluate.should_not be_nil
      instructions = evaluate.not_nil!.blocks.flat_map(&.instructions)
      calls = instructions.compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      calls.none? { |call| call.method_name == "[]$Adamas::Compiler::Frontend::ExprId" }.should be_true
      calls.any? do |call|
        call.virtual &&
          (call.method_name.includes?("Adamas::Compiler::Frontend::AstArena#[]") ||
            call.method_name.includes?("Adamas::Compiler::Frontend::VirtualArena#[]") ||
            call.method_name.includes?("Adamas::Compiler::Frontend::PageArena#[]"))
      end.should be_true

      dispatch_call = calls.find do |call|
        call.virtual &&
          (call.method_name.includes?("Adamas::Compiler::Frontend::AstArena#[]") ||
            call.method_name.includes?("Adamas::Compiler::Frontend::VirtualArena#[]") ||
            call.method_name.includes?("Adamas::Compiler::Frontend::PageArena#[]"))
      end
      dispatch_call.should_not be_nil
      receiver = instructions.find { |instruction| instruction.id == dispatch_call.not_nil!.receiver_value }
      receiver.should_not be_nil
      if copy = receiver.not_nil!.as?(Adamas::HIR::Copy)
        copy_desc = converter.module.get_type_descriptor(copy.type)
        copy_desc.should_not be_nil
        copy_desc.not_nil!.kind.should eq(Adamas::HIR::TypeKind::Union)
        instructions.find { |instruction| instruction.id == copy.source }.should_not be_nil
        instructions.find { |instruction| instruction.id == copy.source }.not_nil!.should be_a(Adamas::HIR::FieldGet)
      else
        receiver.not_nil!.should be_a(Adamas::HIR::FieldGet)
      end

      field = instructions.compact_map { |instruction| instruction.as?(Adamas::HIR::FieldGet) }
        .find { |instruction| instruction.field_name == "@arena" }
      field.should_not be_nil
      field.not_nil!.type.should eq(arena_ivar.not_nil!.type)
      field_desc = converter.module.get_type_descriptor(field.not_nil!.type)
      field_desc.should_not be_nil
      field_desc.not_nil!.kind.should eq(Adamas::HIR::TypeKind::Union)
    end

    it "keeps compact source-backed ivar annotations after empty initialize storage" do
      converter = lower_source_backed_program_with_empty_initialize_params(<<-CRYSTAL)
        module Frontend
          class Arena
          end
        end

        module Semantic
          class Holder
            def initialize(@arena : Frontend::Arena)
              @arena = "stale"
            end
          end
        end
      CRYSTAL
      converter.fixup_inherited_ivars

      arena_ivar = converter.class_info["Semantic::Holder"].ivars.find { |ivar| ivar.name == "@arena" }
      arena_ivar.should_not be_nil
      arena_ivar.not_nil!.type.should_not eq(Adamas::HIR::TypeRef::STRING)
      converter.module.get_type_descriptor(arena_ivar.not_nil!.type).not_nil!.name.should eq("Frontend::Arena")
    end

    it "resolves a sibling alias from a nested semantic class before alias registration" do
      converter = lower_program_with_main(<<-CRYSTAL)
        module Adamas
          module Compiler
            module Semantic
              class MacroExpander
                def initialize(@arena : Frontend::ArenaLike)
                end

                def evaluate_macro_body(id : Frontend::ExprId) : Frontend::Node
                  @arena[id]
                end
              end
            end

            module Frontend
              class Node
              end

              struct ExprId
              end

              class AstArena
                def [](id : ExprId) : Node
                  Node.new
                end
              end

              class VirtualArena
                def [](id : ExprId) : Node
                  Node.new
                end
              end

              class PageArena
                def [](id : ExprId) : Node
                  Node.new
                end
              end

              alias ArenaLike = AstArena | VirtualArena | PageArena
            end
          end
        end

        Adamas::Compiler::Semantic::MacroExpander.new(
          Adamas::Compiler::Frontend::AstArena.new
        ).evaluate_macro_body(Adamas::Compiler::Frontend::ExprId.new)
      CRYSTAL
      converter.fixup_inherited_ivars

      owner_name = "Adamas::Compiler::Semantic::MacroExpander"
      class_info = converter.class_info[owner_name]
      arena_ivar = class_info.ivars.find { |ivar| ivar.name == "@arena" }
      arena_ivar.should_not be_nil
      arena_ivar.not_nil!.type.should_not eq(Adamas::HIR::TypeRef::VOID)
      arena_type = converter.module.get_type_descriptor(arena_ivar.not_nil!.type)
      arena_type.should_not be_nil
      arena_type.not_nil!.kind.should eq(Adamas::HIR::TypeKind::Union)
      arena_type.not_nil!.name.should eq(
        "Adamas::Compiler::Frontend::AstArena | Adamas::Compiler::Frontend::PageArena | Adamas::Compiler::Frontend::VirtualArena"
      )

      evaluate = converter.module.functions.find { |func| func.name.includes?("MacroExpander#evaluate_macro_body") }
      evaluate.should_not be_nil
      instructions = evaluate.not_nil!.blocks.flat_map(&.instructions)
      calls = instructions.compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      calls.none? { |call| call.method_name == "[]$Adamas::Compiler::Frontend::ExprId" }.should be_true
      calls.any? do |call|
        call.virtual &&
          (call.method_name.includes?("Adamas::Compiler::Frontend::AstArena#[]") ||
            call.method_name.includes?("Adamas::Compiler::Frontend::VirtualArena#[]") ||
            call.method_name.includes?("Adamas::Compiler::Frontend::PageArena#[]"))
      end.should be_true

      dispatch_call = calls.find do |call|
        call.virtual &&
          (call.method_name.includes?("Adamas::Compiler::Frontend::AstArena#[]") ||
            call.method_name.includes?("Adamas::Compiler::Frontend::VirtualArena#[]") ||
            call.method_name.includes?("Adamas::Compiler::Frontend::PageArena#[]"))
      end
      dispatch_call.should_not be_nil
      receiver = instructions.find { |instruction| instruction.id == dispatch_call.not_nil!.receiver_value }
      receiver.should_not be_nil
      if copy = receiver.not_nil!.as?(Adamas::HIR::Copy)
        copy_desc = converter.module.get_type_descriptor(copy.type)
        copy_desc.should_not be_nil
        copy_desc.not_nil!.kind.should eq(Adamas::HIR::TypeKind::Union)
        instructions.find { |instruction| instruction.id == copy.source }.should_not be_nil
        instructions.find { |instruction| instruction.id == copy.source }.not_nil!.should be_a(Adamas::HIR::FieldGet)
      else
        receiver.not_nil!.should be_a(Adamas::HIR::FieldGet)
      end

      field = instructions.compact_map { |instruction| instruction.as?(Adamas::HIR::FieldGet) }
        .find { |instruction| instruction.field_name == "@arena" }
      field.should_not be_nil
      field.not_nil!.type.should eq(arena_ivar.not_nil!.type)
      field_desc = converter.module.get_type_descriptor(field.not_nil!.type)
      field_desc.should_not be_nil
      field_desc.not_nil!.kind.should eq(Adamas::HIR::TypeKind::Union)
    end

    it "prefers a deeper lexical Frontend over a sibling namespace with the same alias" do
      converter = lower_program_with_main(<<-CRYSTAL)
        module Adamas
          module Compiler
            module Semantic
              module Frontend
                alias ArenaLike = String
              end

              class MacroExpander
                def initialize(@arena : Frontend::ArenaLike)
                end
              end
            end

            module Frontend
              class AstArena
              end

              class VirtualArena
              end

              class PageArena
              end

              alias ArenaLike = AstArena | VirtualArena | PageArena
            end
          end
        end
      CRYSTAL
      converter.fixup_inherited_ivars

      owner_name = "Adamas::Compiler::Semantic::MacroExpander"
      arena_ivar = converter.class_info[owner_name].ivars.find { |ivar| ivar.name == "@arena" }
      arena_ivar.should_not be_nil
      arena_ivar.not_nil!.type.should eq(Adamas::HIR::TypeRef::STRING)
    end

    it "keeps the declared union owner for ivar indexing" do
      converter = lower_program_with_main(<<-CRYSTAL)
        module Semantic
          class MacroExpander
            @arena : Frontend::ArenaLike

            def initialize(@arena : Frontend::ArenaLike)
            end

            def evaluate(id : Frontend::ExprId) : Frontend::Node
              @arena[id]
            end
          end
        end

        module Frontend
          class Node
          end

          struct ExprId
          end

          class AstArena
            def [](id : ExprId) : Node
              Node.new
            end
          end

          class VirtualArena
            def [](id : ExprId) : Node
              Node.new
            end
          end

          class PageArena
            def [](id : ExprId) : Node
              Node.new
            end
          end

          alias ArenaLike = AstArena | VirtualArena | PageArena
        end

        Semantic::MacroExpander.new(Frontend::AstArena.new).evaluate(Frontend::ExprId.new)
      CRYSTAL

      evaluate = converter.module.functions.find { |func| func.name.includes?("MacroExpander#evaluate") }
      evaluate.should_not be_nil
      calls = evaluate.not_nil!.blocks.flat_map(&.instructions).compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      calls.none? { |call| call.method_name == "[]$Frontend::ExprId" }.should be_true
      calls.any? { |call| call.method_name.includes?("AstArena#[]") || call.method_name.includes?("VirtualArena#[]") || call.method_name.includes?("PageArena#[]") }.should be_true
      calls.any?(&.virtual).should be_true
      receiver = calls.first.receiver_value
      receiver_instruction = evaluate.not_nil!.blocks.flat_map(&.instructions).find { |instruction| instruction.id == receiver }
      receiver_instruction.should_not be_nil
      receiver_desc = converter.module.get_type_descriptor(receiver_instruction.not_nil!.type)
      receiver_desc.should_not be_nil
      receiver_desc.not_nil!.kind.should eq(Adamas::HIR::TypeKind::Union)
    end

    it "keeps an explicit union field typed without an alias placeholder" do
      converter = lower_program_with_main(<<-CRYSTAL)
        module Frontend
          class Node
          end

          struct ExprId
          end

          class AstArena
            def [](id : ExprId) : Node
              Node.new
            end
          end

          class VirtualArena
            def [](id : ExprId) : Node
              Node.new
            end
          end

          class PageArena
            def [](id : ExprId) : Node
              Node.new
            end
          end

          alias ArenaLike = AstArena | VirtualArena | PageArena
        end

        module Semantic
          class MacroExpander
            @arena : Frontend::AstArena | Frontend::VirtualArena | Frontend::PageArena

            def initialize(@arena : Frontend::AstArena | Frontend::VirtualArena | Frontend::PageArena)
            end

            def evaluate(id : Frontend::ExprId) : Frontend::Node
              @arena[id]
            end
          end

          class AliasExpander
            @arena : Frontend::ArenaLike

            def initialize(@arena : Frontend::ArenaLike)
            end

            def evaluate(id : Frontend::ExprId) : Frontend::Node
              @arena[id]
            end
          end
        end

        Semantic::MacroExpander.new(Frontend::AstArena.new).evaluate(Frontend::ExprId.new)
        Semantic::AliasExpander.new(Frontend::AstArena.new).evaluate(Frontend::ExprId.new)
      CRYSTAL

      evaluate = converter.module.functions.find { |func| func.name.includes?("MacroExpander#evaluate") }
      evaluate.should_not be_nil
      calls = evaluate.not_nil!.blocks.flat_map(&.instructions).compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      calls.any?(&.virtual).should be_true
      receiver = calls.first.receiver_value
      receiver_instruction = evaluate.not_nil!.blocks.flat_map(&.instructions).find { |instruction| instruction.id == receiver }
      receiver_instruction.should_not be_nil
      receiver_instruction.not_nil!.should be_a(Adamas::HIR::FieldGet)
      receiver_desc = converter.module.get_type_descriptor(receiver_instruction.not_nil!.type)
      receiver_desc.should_not be_nil
      receiver_desc.not_nil!.kind.should eq(Adamas::HIR::TypeKind::Union)

      alias_evaluate = converter.module.functions.find { |func| func.name.includes?("AliasExpander#evaluate") }
      alias_evaluate.should_not be_nil
      alias_calls = alias_evaluate.not_nil!.blocks.flat_map(&.instructions).compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      alias_calls.any?(&.virtual).should be_true
      alias_receiver = alias_calls.first.receiver_value
      alias_receiver_instruction = alias_evaluate.not_nil!.blocks.flat_map(&.instructions).find { |instruction| instruction.id == alias_receiver }
      alias_receiver_instruction.should_not be_nil
      alias_receiver_instruction.not_nil!.should be_a(Adamas::HIR::FieldGet)
      alias_receiver_desc = converter.module.get_type_descriptor(alias_receiver_instruction.not_nil!.type)
      alias_receiver_desc.should_not be_nil
      alias_receiver_desc.not_nil!.kind.should eq(Adamas::HIR::TypeKind::Union)
    end

    it "does not canonicalize a late tagged-union alias as an all-reference owner" do
      converter = lower_program_with_main(<<-CRYSTAL)
        module Semantic
          class ValueExpander
            @value : Frontend::TaggedValue

            def initialize(@value : Frontend::TaggedValue)
            end

            def evaluate(index : Int32) : Frontend::TaggedValue
              @value[index]
            end
          end
        end

        module Frontend
          alias TaggedValue = Int32 | UInt32
        end

        Semantic::ValueExpander.new(1).evaluate(0)
      CRYSTAL

      evaluate = converter.module.functions.find { |func| func.name.includes?("ValueExpander#evaluate$Int32") }
      evaluate.should_not be_nil
      calls = evaluate.not_nil!.blocks.flat_map(&.instructions).compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      calls.none?(&.virtual).should be_true
      receiver_ids = calls.map(&.receiver_value)
      receiver_ids.each do |receiver_id|
        receiver = evaluate.not_nil!.blocks.flat_map(&.instructions).find { |instruction| instruction.id == receiver_id }
        receiver.should_not be_nil
        receiver.not_nil!.type.should_not eq(converter.__test_type_ref_for_name("Int32 | UInt32"))
      end
      field = evaluate.not_nil!.blocks.flat_map(&.instructions).compact_map { |instruction| instruction.as?(Adamas::HIR::FieldGet) }
        .find { |instruction| instruction.field_name == "@value" }
      field.should_not be_nil
      descriptor = converter.module.get_type_descriptor(field.not_nil!.type)
      descriptor.should_not be_nil
      descriptor.not_nil!.kind.should_not eq(Adamas::HIR::TypeKind::Union)
    end

    it "registers an explicitly tagged ivar declaration when concrete node RTTI is erased" do
      arena = Adamas::Compiler::Frontend::AstArena.new
      span = Adamas::Compiler::Frontend::Span.zero
      ivar_name = "@entries"
      ivar_type_name = "Pointer(Hash::Entry(String, Nil))"
      class_source_name = "Hash"
      arena.retain_source(ivar_name)
      arena.retain_source(ivar_type_name)
      arena.retain_source(class_source_name)

      erased = ErasedInstanceVarDeclNode.new(span, ivar_name.to_slice, ivar_type_name.to_slice)
      erased.is_a?(Adamas::Compiler::Frontend::InstanceVarDeclNode).should be_false
      decl_id = arena.add_typed(erased)
      class_node = Adamas::Compiler::Frontend::ClassNode.new(
        span,
        class_source_name.to_slice,
        nil,
        [decl_id],
        nil,
        false
      )
      converter = Adamas::HIR::AstToHir.new(arena)
      owner_name = "Hash(String, Nil)"
      converter.__test_register_concrete_class(class_node, owner_name)

      class_info = converter.class_info[owner_name]
      class_info.ivars.size.should eq(1)
      entries = class_info.ivars.first
      entries.name.should eq(ivar_name)
      # The 4-byte class type-id header is followed by pointer alignment.
      entries.offset.should eq(8)
      descriptor = converter.module.get_type_descriptor(entries.type)
      descriptor.should_not be_nil
      descriptor.not_nil!.kind.should eq(Adamas::HIR::TypeKind::Pointer)
      descriptor.not_nil!.name.should eq(ivar_type_name)
    end

    it "retains the specialized pointer descriptor and lowers indexing as PointerLoad" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class Hash(K, V)
          @entries : Pointer(Entry(K, V))

          def initialize(@entries : Pointer(Entry(K, V)))
          end

          def get_entry(index : Int32) : Entry(K, V)
            @entries[index]
          end

          struct Entry(K, V)
            def initialize(@key : K, @value : V)
            end
          end
        end

        def exercise(table : Hash(String, Nil))
          table.get_entry(0)
        end

        exercise(uninitialized Hash(String, Nil))
      CRYSTAL

      target_name = "Hash(String, Nil)#get_entry$Int32"
      get_entry_functions = converter.module.functions.select { |candidate| candidate.name == target_name }
      get_entry_functions.size.should eq(1)
      func = get_entry_functions.first

      instructions = func.blocks.flat_map(&.instructions)
      entries_field_gets = instructions.compact_map { |inst| inst.as?(Adamas::HIR::FieldGet) }
        .select { |inst| inst.field_name == "@entries" }
      entries_field_gets.size.should eq(1)
      field_get = entries_field_gets.first
      field_desc = converter.module.get_type_descriptor(field_get.type)
      field_desc.should_not be_nil
      field_desc.not_nil!.kind.should eq(Adamas::HIR::TypeKind::Pointer)
      field_desc.not_nil!.name.should eq("Pointer(Hash::Entry(String, Nil))")

      pointer_loads = instructions.compact_map { |inst| inst.as?(Adamas::HIR::PointerLoad) }
      pointer_loads.size.should eq(1)
      pointer_load = pointer_loads.first
      pointer_load.index.should_not be_nil
      converter.__test_get_type_name_from_ref(pointer_load.type)
        .should eq("Hash::Entry(String, Nil)")

      calls = instructions.compact_map { |inst| inst.as?(Adamas::HIR::Call) }
      calls.none? { |call| call.method_name == "[]$Int32" }.should be_true
      calls.none? { |call| call.method_name.includes?("Pointer#[]$Int32") }.should be_true
    end

    it "keeps user-defined indexing as normal method dispatch" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class UserIndex
          def [](index : Int32) : Int32
            index
          end
        end

        def exercise_index(value : UserIndex)
          value[3]
        end

        exercise_index(UserIndex.new)
      CRYSTAL

      exercise = converter.module.functions.find { |func| func.name.starts_with?("exercise_index") }.not_nil!
      calls = exercise.blocks.flat_map(&.instructions).compact_map { |inst| inst.as?(Adamas::HIR::Call) }
      calls.any? { |call| call.method_name.includes?("UserIndex#[]") }.should be_true
      exercise.blocks.flat_map(&.instructions).none?(&.is_a?(Adamas::HIR::PointerLoad)).should be_true
    end
  end

  describe "unreachable sequential lowering" do
    it "continues a def body after a leading if materializes a non-void helper" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class SequenceBox(T)
          def helper : Int32
            4
          end

          def probe(flag : Bool) : Int32
            if flag
              value = helper
            end

            result = 7
            result
          end
        end

        SequenceBox(Int32).new.probe(false)
      CRYSTAL

      converter.__test_lower_function_if_needed("SequenceBox(Int32)#probe$Bool")
      probe = converter.module.function_by_name("SequenceBox(Int32)#probe$Bool")
      probe.should_not be_nil
      text = hir_text(probe.not_nil!)
      text.should contain("SequenceBox(Int32)#helper")
      text.should contain("literal 7")
    end

    it "does not lower statements after an explicit return" do
      func = lower_function("def foo; return 1; 2; end")
      text = hir_text(func)

      text.should contain("literal 1")
      text.should_not contain("literal 2")
    end

    it "does not lower statements after raise" do
      func = lower_function("def foo; raise \"x\"; 1; end")
      text = hir_text(func)

      text.should_not contain("literal 1")
    end

    it "does not reuse a terminating branch capture box for a different fallthrough local" do
      func, converter = lower_function_with_converter(<<-CRYSTAL)
        def probe(flag : Bool)
          if flag
            values = Set(UInt32).new
            values << 1_u32
            return values.includes?(1_u32)
          end

          values = [] of UInt32
          values << 2_u32
          contains = ->(value : UInt32) { values.includes?(value) }
          contains.call(2_u32)
        end
      CRYSTAL

      set_type = converter.__test_type_ref_for_name("Set(UInt32)")
      array_type = converter.__test_type_ref_for_name("Array(UInt32)")
      value_locals = func.blocks.flat_map(&.instructions).compact_map do |instruction|
        local = instruction.as?(Adamas::HIR::Local)
        local if local && local.name == "values"
      end

      value_locals.map(&.type).should contain(set_type)
      value_locals.map(&.type).should contain(array_type)

      closure = func.blocks.flat_map(&.instructions)
        .find(&.is_a?(Adamas::HIR::MakeClosure))
        .not_nil!.as(Adamas::HIR::MakeClosure)
      capture = closure.captures.find { |item| item.name == "values" }.not_nil!

      capture.boxed.should be_true
      capture.payload_type.should eq(array_type)

      text = hir_text(func)
      text.should contain("Array(UInt32)#<<$UInt32")
      text.should_not contain("Array(String)#<<$String")
    end
  end

  describe "generic receiver union specialization" do
    it "does not collapse union type args to Pointer(Void) when instantiating generic receivers" do
      code = <<-CRYSTAL
        module Indexable(T)
          abstract def size : Int32
          abstract def unsafe_fetch(i : Int32) : T

          def [](i : Int32) : T
            unsafe_fetch(i)
          end

          private class ItemIterator(A, T)
            def initialize(@array : A, @index = 0)
            end

            def next : T
              if @index >= @array.size
                raise "stop"
              end
              value = @array[@index]
              @index += 1
              value
            end
          end

          def each
            ItemIterator(self, T).new(self)
          end
        end

        struct Box(T)
          include Indexable(T)

          def size : Int32
            0
          end

          def unsafe_fetch(i : Int32) : T
            uninitialized T
          end
        end

        def foo(b : Box(Int32 | Pointer(UInt8)))
          b.each
        end

        foo(Box(Int32 | Pointer(UInt8)).new)
      CRYSTAL

      converter = lower_program_with_main(code)
      func = converter.module.functions.find { |f| f.name.starts_with?("Box(") && f.name.includes?("#each") }
      func.should_not be_nil

      text = hir_text(func.not_nil!)
      text.should_not contain("ItemIterator(Pointer(Void), Pointer(Void))")
      text.should_not contain("Pointer(Void)#size")
    end

    it "keeps tuple parameter shape in typeof-based generic specializations" do
      converter = lower_program(<<-CRYSTAL)
        class Holder(T)
          def self.marker
            1
          end
        end

        def wrap(args : Tuple(Float64))
          Holder(typeof(args)).marker
        end

        wrap({0.125_f64})
      CRYSTAL

      wrap = converter.module.functions.find do |func|
        func.name == "wrap" || func.name.starts_with?("wrap$")
      end
      wrap.should_not be_nil
      text = hir_text(wrap.not_nil!)

      text.should contain("Holder(Tuple(Float64)).marker")
      text.should_not contain("Holder(Pointer(Void)).marker")
    end

    it "keeps tuple indexing on the concrete tuple element type" do
      converter = lower_program(<<-CRYSTAL)
        class Formatter(T)
          def initialize(@args : T)
          end

          def arg_at
            @args[0]
          end
        end

        def fetch_arg(formatter : Formatter(Tuple(Float64)))
          formatter.arg_at
        end
      CRYSTAL

      arg_at = converter.module.functions.find do |func|
        func.name.starts_with?("Formatter(Tuple(Float64))#arg_at")
      end
      arg_at.should_not be_nil
      arg_at_type = converter.__test_get_type_name_from_ref(arg_at.not_nil!.return_type)
      arg_at_type.should eq("Float64")

      text = hir_text(arg_at.not_nil!)
      text.should_not contain("Pointer(Void)")
    end

    it "keeps String::Builder exact through inspect without specializing unrelated IO methods" do
      source = <<-CRYSTAL
        abstract class IO
        end

        class String::Builder < IO
        end

        class Object
          def inspect : String
            inspect(String::Builder.new)
            ""
          end

          def inspect(io : IO) : Nil
          end
        end

        class Reference < Object
        end

        class BuilderBox(T) < Reference
          def inspect(io : IO) : Nil
            to_s(io)
          end

          def to_s(io : IO) : Nil
            render(io)
          end

          def render(io : IO) : Nil
          end
        end
      CRYSTAL

      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
      converter.arena = arena
      class_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode) }
      class_nodes.each { |node| converter.register_class(node) }
      converter.module.class_parents["String::Builder"] = "IO"
      converter.__test_monomorphize_generic_class("BuilderBox", ["Int32"], "BuilderBox(Int32)")

      converter.__test_lower_function_if_needed("BuilderBox(Int32)#inspect")
      converter.__test_lower_function_if_needed("BuilderBox(Int32)#inspect$String::Builder")
      converter.__test_lower_function_if_needed("BuilderBox(Int32)#to_s$String::Builder")
      converter.__test_lower_function_if_needed("BuilderBox(Int32)#render$IO")

      inspect = converter.module.function_by_name("BuilderBox(Int32)#inspect$String::Builder")
      inspect.should_not be_nil
      converter.__test_get_type_name_from_ref(inspect.not_nil!.params[1].type).should eq("String::Builder")

      to_s = converter.module.function_by_name("BuilderBox(Int32)#to_s$String::Builder")
      to_s.should_not be_nil
      converter.__test_get_type_name_from_ref(to_s.not_nil!.params[1].type).should eq("String::Builder")

      converter.module.function_by_name("BuilderBox(Int32)#render$String::Builder").should be_nil
      converter.module.function_by_name("BuilderBox(Int32)#render$IO").should_not be_nil
    end

    it "prunes impossible numeric named-container branches before lowering their body" do
      converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
        def guarded_numeric_lookup(flag : Bool, value : Float64, key : String) : Float64
          if flag && value.is_a?(Hash)
            value[key]
          end
          value
        end

        guarded_numeric_lookup(true, 1.25_f64, "x")
      CRYSTAL

      function = converter.module.functions.find do |candidate|
        candidate.name.starts_with?("guarded_numeric_lookup")
      end
      function.should_not be_nil

      calls = function.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end
      calls.none? { |call| call.method_name.includes?("Float64#[]$String") }.should be_true
    end

    it "preserves dynamic receiver evaluation before pruning an impossible named-container branch" do
      converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
        def dynamic_numeric_value(value : Float64) : Float64
          value
        end

        def guarded_dynamic_lookup(flag : Bool, value : Float64, key : String) : Float64
          if flag && dynamic_numeric_value(value).is_a?(Hash)
            value[key]
          end
          value
        end

        guarded_dynamic_lookup(true, 1.25_f64, "x")
      CRYSTAL

      function = converter.module.functions.find do |candidate|
        candidate.name.starts_with?("guarded_dynamic_lookup")
      end
      function.should_not be_nil

      calls = function.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end
      calls.any? { |call| call.method_name.starts_with?("dynamic_numeric_value") }.should be_true
      calls.none? { |call| call.method_name.includes?("Float64#[]$String") }.should be_true
    end

    it "preserves concrete Hash and NamedTuple indexing behind named-container guards" do
      hash_converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
        def guarded_hash_lookup(value : Hash(String, Int32), key : String) : Int32
          if value.is_a?(Hash)
            return value[key]
          end
          0
        end

        guarded_hash_lookup({"x" => 3}, "x")
      CRYSTAL

      hash_calls = hash_converter.module.functions.flat_map(&.blocks).flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end
      hash_calls.any? { |call| call.method_name == "Hash(String, Int32)#[]$String" }.should be_true

      named_converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
        def guarded_named_lookup(value : NamedTuple(x: Int32), key : String) : Int32
          if value.is_a?(NamedTuple)
            return value[key]
          end
          0
        end

        guarded_named_lookup({x: 3}, "x")
      CRYSTAL

      named_calls = named_converter.module.functions.flat_map(&.blocks).flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end
      named_calls.any? do |call|
        call.method_name.includes?("NamedTuple(") && call.method_name.includes?("#[]$String")
      end.should be_true
    end

    it "preserves concrete owner type params for generic-module unsafe_as and constants" do
      converter = lower_program_with_main(<<-CRYSTAL)
        module Reint(F, U)
          def self.bits(num : F)
            u = num.unsafe_as(U)
            u & U::MAX
          end
        end

        Reint(Float64, UInt64).bits(1.5_f64)
      CRYSTAL

      uint64_ref = converter.__test_type_ref_for_name("UInt64")

      converter.__test_lower_function_if_needed("Reint(Float64, UInt64).bits$Float64")
      func = converter.module.function_by_name("Reint(Float64, UInt64).bits$Float64")
      func.should_not be_nil

      text = hir_text(func.not_nil!)
      # Semantic checks — the concrete `F` type param must be materialized as UInt64
      # inside the generic-module body:
      #   - a cast to UInt64 is emitted (SSA ids shift as lowering evolves, don't pin)
      #   - the fallback generic `Object#unsafe_as$T` wrapper is not used
      #   - the `Tuple#to_i` misroute is not taken
      text.should match(/cast %\d+ as #{uint64_ref.id}\b/)
      text.should_not contain("Object#unsafe_as$T")
      text.should_not contain("Tuple#to_i")
    end

    it "preserves parameter reassignments across statically selected if branches" do
      converter = lower_program(<<-CRYSTAL)
        def foo(x : Bool?)
          if true
            x = true
          end
          x
        end
      CRYSTAL

      foo = converter.module.function_by_name("foo$Nil | Bool")
      foo.should_not be_nil

      exit_term = foo.not_nil!.get_block(foo.not_nil!.entry_block).terminator
      exit_term.should be_a(Adamas::HIR::Return)
      return_value = exit_term.as(Adamas::HIR::Return).value
      return_value.should_not be_nil

      return_copy = foo.not_nil!.blocks.flat_map(&.instructions).find do |inst|
        inst.is_a?(Adamas::HIR::Copy) && inst.id == return_value
      end
      return_copy.should_not be_nil
      return_copy.not_nil!.as(Adamas::HIR::Copy).source.should_not eq(foo.not_nil!.params.first.id)
    end

    it "materializes inherited nested struct dispatch under the concrete owner" do
      converter = lower_program(<<-CRYSTAL)
        module Renderable
          def render : Int32
            7
          end
        end

        module Outer
          module Inner
            struct Point
              include Renderable
            end
          end
        end

        def render_point(point : Outer::Inner::Point)
          point.render
        end
      CRYSTAL

      render_point = converter.module.functions.find { |func| func.name.starts_with?("render_point$") }
      render_point.should_not be_nil
      render_type = converter.__test_get_type_name_from_ref(render_point.not_nil!.return_type)
      render_type.should eq("Int32")
      text = hir_text(render_point.not_nil!)
      text.should contain("Outer::Inner::Point#render")
      text.should_not contain("Struct#render")
    end

    it "keeps concrete generic receiver targets lowerable on demand" do
      converter = lower_program(<<-CRYSTAL)
        struct Point
        end

        class Bag(T)
          def render(value : T) : T
            value
          end
        end

        def render_point(bag : Bag(Point), point : Point)
          bag.render(point)
        end
      CRYSTAL

      render = converter.module.functions.find do |func|
        func.name.starts_with?("Bag(Point)#render$")
      end
      render.should_not be_nil
      converter.__test_get_type_name_from_ref(render.not_nil!.return_type).should eq("Point")
      hir_text(render.not_nil!).should_not contain("Pointer(Void)")
    end

    it "does not materialize unrelated generic receiver targets" do
      converter = lower_program(<<-CRYSTAL)
        struct Point
        end

        class Bag(T)
          def render(value : T) : T
            value
          end
        end

        def render_point(bag : Bag(Point), point : Point)
          bag.render(point)
        end
      CRYSTAL

      converter.module.functions.any? { |func| func.name.starts_with?("Bag(Point)#render$") }.should be_true
      converter.module.functions.any? { |func| func.name.starts_with?("Bag(Int32)#render$") }.should be_false
    end

    it "preserves concrete generic receiver owners when lowering inherited generic bodies" do
      converter = lower_program(<<-CRYSTAL)
        struct Point
          end

        module Renderable(T)
          def render(value : T) : T
            value
          end
        end

        class Bag(T)
          include Renderable(T)
        end

        def render_point(bag : Bag(Point), point : Point)
          bag.render(point)
        end
      CRYSTAL

      render_point = converter.module.functions.find { |func| func.name.starts_with?("render_point$") }
      render_point.should_not be_nil
      converter.__test_get_type_name_from_ref(render_point.not_nil!.return_type).should eq("Point")
      text = hir_text(render_point.not_nil!)
      text.should contain("Bag(Point)#render")
      text.should_not contain("Renderable(T)#render")
      text.should_not contain("Pointer(Void)")
    end

    it "suppresses speculative arbitrary concrete callees inside active lowering" do
      arena = parse("1")[0]
      converter = Adamas::HIR::AstToHir.new(arena)
      converter.arena = arena

      converter.__test_queue_pending_inside_lowering("Array(Point)#inspect$IO")

      converter.__test_pending_function?("Array(Point)#inspect$IO").should be_false
      converter.__test_pending_function_occurrences("Array(Point)#inspect$IO").should eq(0)
      converter.__test_rta_called_method?("Array(Point)#inspect$IO").should be_false
      converter.__test_rta_called_method?("Array(Point)#inspect").should be_false
      converter.__test_rta_called_method_part?("inspect$IO").should be_false
      converter.__test_rta_called_method_part?("inspect").should be_false
    end

    it "keeps speculative callee suppression exact-name idempotent" do
      arena = parse("1")[0]
      converter = Adamas::HIR::AstToHir.new(arena)
      converter.arena = arena

      converter.__test_queue_pending_inside_lowering("Array(Point)#inspect$IO")
      converter.__test_pending_function?("Array(Point)#inspect$IO").should be_false
      converter.__test_pending_function_occurrences("Array(Point)#inspect$IO").should eq(0)
      converter.__test_rta_called_method?("Array(Point)#inspect$IO").should be_false

      converter.__test_queue_pending_inside_lowering("Array(Point)#inspect$IO")
      converter.__test_pending_function_occurrences("Array(Point)#inspect$IO").should eq(0)
      converter.__test_rta_called_method?("Array(Point)#inspect$IO").should be_false
    end
  end

  describe "lazy RTA root demand" do
    it "records direct calls emitted by the synthetic main as exact demand" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class RootDemandRunner
          def run : Int32
            7
          end
        end

        def consume_root_demand(value : Int32) : Int32
          value
        end

        consume_root_demand(RootDemandRunner.new.run)
      CRYSTAL

      main = converter.module.function_by_name("__adamas_main")
      main.should_not be_nil
      hir_text(main.not_nil!).should contain("RootDemandRunner#run")

      converter.__test_process_pending_lower_functions

      converter.__test_rta_called_method?("RootDemandRunner#run").should be_true
      converter.__test_rta_called_method?("Array(Point)#inspect$IO").should be_false
    end

    it "does not infer parent instance liveness from an inherited direct-call symbol" do
      source = <<-CRYSTAL
        class Object
          def probe : Int32
            1
          end
        end

        class RtaCallOwnerParent < Object
          def touch : Int32
            2
          end

          def probe : Int32
            3
          end
        end

        class RtaCallOwnerChild(T) < RtaCallOwnerParent
          def probe : Int32
            4
          end
        end

        def touch_inherited(value : RtaCallOwnerChild(Int32)) : Int32
          value.touch
        end
      CRYSTAL

      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena
      class_nodes = exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
      end
      def_nodes = exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode)
      end
      class_nodes.each { |node| converter.register_class(node) }
      def_nodes.each { |node| converter.register_function(node) }
      converter.__test_monomorphize_generic_class(
        "RtaCallOwnerChild",
        ["Int32"],
        "RtaCallOwnerChild(Int32)",
      )

      converter.__test_set_lazy_rta_active(true)
      converter.__test_mark_live_type("RtaCallOwnerChild(Int32)")
      converter.__test_record_virtual_target(
        "Object",
        "probe",
        [] of Adamas::HIR::TypeRef,
      )

      child_target = converter.module.functions.find do |func|
        func.name.starts_with?("RtaCallOwnerChild(Int32)#probe")
      end
      child_target.should_not be_nil
      converter.module.has_function_with_body?(child_target.not_nil!.name).should be_true
      converter.module.functions.any? do |func|
        func.name.starts_with?("RtaCallOwnerParent#probe") &&
          converter.module.has_function_with_body?(func.name)
      end.should be_false

      touch_node = def_nodes.find do |node|
        String.new(node.name.not_nil!) == "touch_inherited"
      end
      touch_node.should_not be_nil
      converter.lower_def(touch_node.not_nil!)
      caller = converter.module.functions.find do |func|
        func.name.starts_with?("touch_inherited$")
      end
      caller.should_not be_nil
      inherited_call = caller.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end.find { |call| call.method_name.starts_with?("RtaCallOwnerParent#touch") }
      inherited_call.should_not be_nil
      inherited_call.not_nil!.has_receiver?.should be_true

      converter.__test_scan_hir_function_for_live_types(caller.not_nil!)

      converter.module.functions.any? do |func|
        func.name.starts_with?("RtaCallOwnerParent#probe") &&
          converter.module.has_function_with_body?(func.name)
      end.should be_false

      receiverless = converter.module.create_function(
        "receiverless_call_owner_witness",
        Adamas::HIR::TypeRef::INT32,
      )
      receiverless.get_block(receiverless.entry_block).add(
        Adamas::HIR::Call.without_receiver(
          receiverless.next_value_id,
          Adamas::HIR::TypeRef::INT32,
          "RtaCallOwnerParent#touch",
          [] of Adamas::HIR::ValueId,
        )
      )
      converter.__test_scan_hir_function_for_live_types(receiverless)

      converter.module.functions.any? do |func|
        func.name.starts_with?("RtaCallOwnerParent#probe") &&
          converter.module.has_function_with_body?(func.name)
      end.should be_true
    ensure
      converter.try(&.__test_set_lazy_rta_active(false))
    end
  end

  describe "named arg block overload resolution" do
    it "keeps named arg names when selecting block overloads" do
      converter = lower_program_with_main(<<-CRYSTAL)
        def foo(name = nil, &block)
          block.call
        end

        def foo(*, name = nil, same_thread = false, &block)
          value = same_thread
          block.call
        end

        foo(name: nil, same_thread: false) { 42 }
      CRYSTAL

      main = converter.module.function_by_name("__adamas_main")
      main.should_not be_nil

      text = hir_text(main.not_nil!)
      text.should contain("call foo$Nil_Bool_block")
      text.should_not contain("call foo$arity1")
    end
  end

  describe "allocator lookup recovery" do
    it "binds constructor named arguments through initializer parameter names" do
      source = <<-CRYSTAL
        class NamedSlotProbe
          def initialize(
            @first : Int32 = 1,
            @second : Int32 = 2,
            @third : Int32 = 3,
            @fourth : Int32 = 4,
          )
          end
        end

        class ExplicitNamedNewProbe
          def initialize(
            @first : Int32 = 1,
            @second : Int32 = 2,
            @third : Int32 = 3,
            @fourth : Int32 = 4,
          )
          end

          def self.new(*, value : Int32 = 1) : Int32
            value
          end
        end

        class ExplicitNamedNewBase
          def initialize(
            @first : Int32 = 1,
            @second : Int32 = 2,
            @third : Int32 = 3,
            @fourth : Int32 = 4,
          )
          end

          def self.new(*, value : Int32 = 1) : Int32
            value
          end
        end

        class ExplicitNamedNewChild < ExplicitNamedNewBase
        end

        module ExtendedNamedNew
          def new(*, value : Int32 = 1) : Int32
            value
          end
        end

        class ExtendedNamedNewProbe
          extend ExtendedNamedNew

          def initialize(
            @first : Int32 = 1,
            @second : Int32 = 2,
            @third : Int32 = 3,
            @fourth : Int32 = 4,
          )
          end
        end

        NamedSlotProbe.new(third: 30)
        NamedSlotProbe.new(fourth: 40, second: 20)
        ExplicitNamedNewProbe.new(value: 30)
        ExplicitNamedNewChild.new(value: 30)
        ExtendedNamedNewProbe.new(value: 30)
      CRYSTAL

      # Match the production CLI's lazy ordering: register class signatures,
      # then lower top-level calls before eagerly lowering class bodies.
      arena, roots = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena
      main_exprs = [] of UInt64
      roots.each do |expr_id|
        case node = arena[expr_id]
        when Adamas::Compiler::Frontend::ModuleNode
          converter.register_module(node)
        when Adamas::Compiler::Frontend::ClassNode
          converter.register_class(node)
        when Adamas::Compiler::Frontend::CallNode
          main_exprs << expr_id.index.to_u64
        end
      end
      converter.lower_main(main_exprs)

      main = converter.module.function_by_name("__adamas_main").not_nil!
      constructor_calls = main.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call)).select do |call|
        call.method_name.starts_with?("NamedSlotProbe.new")
      end

      constructor_calls.size.should eq(2)
      constructor_calls.each do |call|
        call.method_name.should eq("NamedSlotProbe.new$Int32_Int32_Int32_Int32")
        call.args.size.should eq(4)
      end

      explicit_new_calls = main.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call)).select do |call|
        (call.method_name.includes?("ExplicitNamedNew") || call.method_name.includes?("ExtendedNamedNewProbe")) &&
          call.method_name.includes?(".new")
      end
      explicit_new_calls.size.should eq(3)
      explicit_new_calls.each do |call|
        call.method_name.should end_with(".new$Int32")
        call.args.size.should eq(1)
      end
    end

    it "binds auto self.new named arguments through initialize" do
      converter = lower_program_with_sources(<<-CRYSTAL)
        class AutoSelfNewProbe
          def initialize(
            @first : Int32 = 1,
            @second : Int32 = 2,
            @third : Int32 = 3,
            @fourth : Int32 = 4,
          )
          end

          def self.build
            self.new(third: 30)
          end
        end
      CRYSTAL

      builder = converter.module.functions.find do |func|
        func.name.starts_with?("AutoSelfNewProbe.build")
      end
      builder.should_not be_nil
      self_new_call = builder.not_nil!.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call)).find do |call|
        call.method_name.starts_with?("AutoSelfNewProbe.new")
      end

      self_new_call.should_not be_nil
      self_new_call.not_nil!.method_name.should eq("AutoSelfNewProbe.new$Int32_Int32_Int32_Int32")
      self_new_call.not_nil!.args.size.should eq(4)
    end

    it "rematerializes a typed initializer body after a completed-state miss" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class RecoveryBox
          def initialize(value : Int32)
            @value = value
          end
        end

        def build_recovery_box
          RecoveryBox.new(7)
        end

        build_recovery_box
      CRYSTAL

      initializer_defs = converter.__test_function_def_names("RecoveryBox#initialize")
      initializer_defs.should_not be_empty
      allocator = converter.module.functions.find { |func| func.name.starts_with?("RecoveryBox.new") }
      allocator.should_not be_nil
      init_call = allocator.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call).try { |call| call if call.method_name.starts_with?("RecoveryBox#initialize") }
      end.first?
      init_call.should_not be_nil
      initializer_name = init_call.not_nil!.method_name
      initializer_defs.should contain(initializer_name)
      converter.module.has_function_with_body?(initializer_name).should be_true
    end

    it "clears stale completed state when an abstract initializer has no body" do
      converter = lower_program_with_main(<<-CRYSTAL)
        abstract class AbstractRecovery
          abstract def initialize(value : Int32)
        end
      CRYSTAL

      initializer_name = converter.__test_function_def_names("AbstractRecovery#initialize").first?
      initializer_name.should_not be_nil
      name = initializer_name.not_nil!
      converter.module.remove_function(name) if converter.module.has_function?(name)
      converter.module.create_function(name, Adamas::HIR::TypeRef::VOID)
      converter.module.has_function_with_body?(name).should be_false
      converter.__test_mark_lowering_completed(name)

      converter.__test_lower_allocator_initializer_body(
        "AbstractRecovery",
        name,
        [Adamas::HIR::TypeRef::INT32],
      )

      converter.module.has_function_with_body?(name).should be_false
      converter.__test_function_lowering_completed?(name).should be_false
    end

    it "generates a class allocator for generic zero-arg .new calls" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class Channel(T)
          def initialize(@capacity = 0)
          end
        end

        ch = Channel(Int32).new
      CRYSTAL

      converter.__test_lower_function_if_needed("Channel(Int32).new")

      allocator = converter.module.function_by_name("Channel(Int32).new")
      allocator.should_not be_nil
      allocator.not_nil!.blocks.any? { |block| !block.instructions.empty? }.should be_true

      allocator_text = hir_text(allocator.not_nil!)
      allocator_text.should contain("Channel(Int32)#initialize$Int32(%0)")
    end

    it "keeps positional constructor overloads ahead of protected named-only initializers" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class SetShape
          getter marker : Int32

          def initialize(initial_capacity = nil)
            @marker = 7
          end

          protected def initialize(*, using_hash @marker : Int32)
            @marker = 99
          end
        end

        class OpenShape
          @marker : Int32

          def initialize(capacity = nil)
            @marker = 1
          end
        end

        def build
          SetShape.new
          SetShape.new(4)
          OpenShape.new(4)
        end

        build
      CRYSTAL

      zero_allocator = converter.module.function_by_name("SetShape.new")
      one_allocator = converter.module.function_by_name("SetShape.new$Int32")
      open_allocator = converter.module.function_by_name("OpenShape.new$Int32")
      zero_allocator.should_not be_nil
      one_allocator.should_not be_nil
      open_allocator.should_not be_nil

      zero_init_calls = zero_allocator.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call).try { |call| call if call.method_name.includes?("SetShape#initialize") }
      end
      one_init_calls = one_allocator.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call).try { |call| call if call.method_name.includes?("SetShape#initialize") }
      end
      open_init_calls = open_allocator.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call).try { |call| call if call.method_name.includes?("OpenShape#initialize") }
      end

      zero_init_calls.size.should eq(1)
      one_init_calls.size.should eq(1)
      zero_init_calls.first.not_nil!.method_name.should eq("SetShape#initialize$Nil")
      one_init_calls.first.not_nil!.method_name.should eq("SetShape#initialize$arity1")
      zero_init_calls.first.not_nil!.args.size.should eq(1)
      one_init_calls.first.not_nil!.args.size.should eq(1)
      open_init_calls.size.should eq(1)
      open_init_calls.first.not_nil!.method_name.should eq("OpenShape#initialize$Int32")
      open_init_calls.first.not_nil!.args.size.should eq(1)
    end

    it "resolves a missing typed allocator initializer by positional call shape" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class SetShape
          def initialize(initial_capacity = nil)
            @marker = 7
          end

          protected def initialize(*, using_hash @marker)
            @marker = 99
          end
        end

        SetShape.new(4)
      CRYSTAL

      converter.__test_allocator_initializer_def_name(
        "SetShape",
        "SetShape#initialize$Int32",
        [Adamas::HIR::TypeRef::INT32],
      ).should eq("SetShape#initialize$arity1")
    end

    it "keeps an explicit nil allocator on the positional initializer" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class SetShape
          def initialize(initial_capacity : Int32? = nil)
            @marker = 7
          end

          protected def initialize(*, using_hash @marker : Int32)
            @marker = 99
          end
        end

        SetShape.new(nil)
      CRYSTAL

      allocator = converter.module.function_by_name("SetShape.new$Nil")
      allocator.should_not be_nil
      calls = allocator.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call).try do |call|
          call if call.method_name.includes?("SetShape#initialize")
        end
      end
      calls.size.should eq(1)
      init = calls.first.not_nil!.method_name
      init.should_not contain("Hash")
      public_init = converter.module.function_by_name(init)
      public_init.should_not be_nil
      hir_text(public_init.not_nil!).should contain("literal 7")
      hir_text(public_init.not_nil!).should_not contain("literal 99")
    end

    it "keeps a concrete optional tail type when forwarding allocator overloads" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class ReceiverCarrier
          def initialize(prefix : Int32, receiver : String? = nil)
            @prefix = prefix
            @receiver = receiver
          end
        end

        ReceiverCarrier.new(1, "self")
        ReceiverCarrier.new(2, nil)
        ReceiverCarrier.new(3)
      CRYSTAL

      allocator = converter.module.function_by_name("ReceiverCarrier.new$Int32_String")
      allocator.should_not be_nil
      allocator.not_nil!.params[0].type.should eq(Adamas::HIR::TypeRef::INT32)
      allocator.not_nil!.params[1].type.should eq(Adamas::HIR::TypeRef::STRING)
      init_calls = allocator.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call).try do |call|
          call if call.method_name.includes?("ReceiverCarrier#initialize")
        end
      end

      init_calls.size.should eq(1)
      init_calls.first.not_nil!.method_name.should eq(
        "ReceiverCarrier#initialize$Int32_String"
      )

      nil_allocator = converter.module.function_by_name("ReceiverCarrier.new$Int32_Nil")
      nil_allocator.should_not be_nil
      nil_call = nil_allocator.not_nil!.blocks.flat_map(&.instructions).find do |instruction|
        instruction.as?(Adamas::HIR::Call).try(&.method_name.includes?("ReceiverCarrier#initialize"))
      end
      nil_call.should_not be_nil
      nil_call.not_nil!.as(Adamas::HIR::Call).method_name.should eq(
        "ReceiverCarrier#initialize$Int32_Nil"
      )

      default_allocator = converter.module.function_by_name("ReceiverCarrier.new$Int32")
      default_allocator.should_not be_nil
      default_call = default_allocator.not_nil!.blocks.flat_map(&.instructions).find do |instruction|
        instruction.as?(Adamas::HIR::Call).try(&.method_name.includes?("ReceiverCarrier#initialize"))
      end
      default_call.should_not be_nil
      default_call.not_nil!.as(Adamas::HIR::Call).method_name.should eq(
        "ReceiverCarrier#initialize$Int32_Nil | String"
      )
    end

    it "does not retarget a positional nilable initializer into a named-only collision" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class OptionalCollision
          def initialize(value : String?)
            @marker = 7
          end

          protected def initialize(*, value : String)
            @marker = 99
          end
        end

        OptionalCollision.new("self")
      CRYSTAL

      allocator = converter.module.function_by_name("OptionalCollision.new$String")
      allocator.should_not be_nil
      init_calls = allocator.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call).try do |call|
          call if call.method_name.includes?("OptionalCollision#initialize")
        end
      end
      init_calls.size.should eq(1)
      init_calls.first.not_nil!.method_name.should eq(
        "OptionalCollision#initialize$Nil | String"
      )

      positional_init = converter.module.function_by_name(
        "OptionalCollision#initialize$Nil | String"
      )
      positional_init.should_not be_nil
      hir_text(positional_init.not_nil!).should contain("literal 7")
      hir_text(positional_init.not_nil!).should_not contain("literal 99")
    end

    it "preserves named constructor identity through allocator overload lookup" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class SetShape(T)
          getter marker : Int32

          protected def initialize(*, using_hash @marker : Int32)
            @marker = 99
          end

          def initialize(initial_capacity : Int32)
            @marker = 7
          end
        end

        SetShape(String).new(initial_capacity: 131072)
      CRYSTAL

      public_name = "SetShape(String)#initialize$Int32_positional"
      allocator = converter.module.function_by_name("SetShape(String).new$Int32")
      allocator.should_not be_nil
      calls = allocator.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call).try do |call|
          call if call.method_name.includes?("SetShape(String)#initialize")
        end
      end
      calls.size.should eq(1)
      calls.first.not_nil!.method_name.should eq(public_name)
      public_init = converter.module.function_by_name(public_name)
      public_init.should_not be_nil
      hir_text(public_init.not_nil!).should contain("literal 7")
      hir_text(public_init.not_nil!).should_not contain("literal 99")
    end

    it "keeps generic positional and named-only initializer identities distinct" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class Hash(K, V)
        end

        class SetShape(T)
          getter marker : Int32

          def initialize(initial_capacity = nil)
            @marker = 7
          end

          protected def initialize(*, using_hash @hash : Hash(T, Nil))
            @marker = 99
          end
        end

        SetShape(Int32).new
        SetShape(Int32).new(4)
      CRYSTAL

      initialize_names = converter.__test_function_def_names("SetShape(Int32)#initialize")
      initialize_names.should contain("SetShape(Int32)#initialize$arity1")
      initialize_names.should contain("SetShape(Int32)#initialize$Hash(Int32, Nil)")
      initialize_names.uniq.size.should eq(initialize_names.size)

      allocator = converter.module.function_by_name("SetShape(Int32).new$Int32")
      allocator.should_not be_nil
      calls = allocator.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call).try { |call| call if call.method_name.includes?("SetShape(Int32)#initialize") }
      end
      calls.size.should eq(1)
      calls.first.not_nil!.method_name.should eq("SetShape(Int32)#initialize$Int32")
    end

    it "does not let a same-typed named-only initializer shadow positional identity" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class SameTypeCollision
          getter marker : Int32

          protected def initialize(*, value : Int32)
            @marker = 99
          end

          def initialize(value : Int32)
            @marker = 7
          end
        end

        SameTypeCollision.new(1)
      CRYSTAL

      allocator = converter.module.function_by_name("SameTypeCollision.new$Int32")
      allocator.should_not be_nil
      call = allocator.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call).try do |candidate|
          candidate if candidate.method_name.includes?("SameTypeCollision#initialize")
        end
      end.first?
      call.should_not be_nil
      selected = call.not_nil!.method_name
      selected.should_not contain("arity")
      body = converter.module.function_by_name(selected)
      body.should_not be_nil
      hir_text(body.not_nil!).should contain("literal 7")
      hir_text(body.not_nil!).should_not contain("literal 99")
    end

    it "recovers a unique positional initializer when typed metadata is stale" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class CorruptLate
          def initialize(value : Int32)
            @marker = 7
          end

          protected def initialize(*, value : String)
            @marker = 99
          end
        end

        CorruptLate.new(1)
      CRYSTAL

      positional_name = "CorruptLate#initialize$Int32"
      converter.__test_corrupt_function_def_param_type(positional_name, "Nil")
      converter.__test_allocator_initializer_direct_shape_compatible?(
        positional_name,
        [Adamas::HIR::TypeRef::INT32],
      ).should be_false
      converter.__test_allocator_initializer_def_name(
        "CorruptLate",
        positional_name,
        [Adamas::HIR::TypeRef::INT32],
      ).should eq(positional_name)
      converter.__test_allocator_unique_positional_def_name_for_base(
        "CorruptLate#initialize",
        "CorruptLate#initialize",
        [Adamas::HIR::TypeRef::INT32],
      ).should eq(positional_name)
    end

    it "fails closed when multiple positional initializer shapes share an arity" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class AmbiguousLate
          def initialize(value : Int32)
            @marker = 7
          end

          def initialize(value : String)
            @marker = 99
          end
        end

        AmbiguousLate.new(1)
      CRYSTAL

      converter.__test_allocator_unique_positional_def_name_for_base(
        "AmbiguousLate#initialize",
        "AmbiguousLate#initialize",
        [Adamas::HIR::TypeRef::INT32],
      ).should be_nil
    end

    it "keeps inherited initializer super dispatch on the defining owner" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class GrandParent
          def initialize(value : Int32)
            @marker = 1
          end
        end

        class Parent < GrandParent
          def initialize(value : Int32)
            super(value)
            @marker = 2
          end
        end

        class Child < Parent
        end

        Child.new(1)
      CRYSTAL

      allocator = converter.module.function_by_name("Child.new$Int32")
      allocator.should_not be_nil
      init_call = allocator.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call).try do |call|
          call if call.method_name.includes?("#initialize")
        end
      end.first?
      init_call.should_not be_nil
      init_call.not_nil!.method_name.should contain("Parent#initialize")

      parent_init = converter.module.function_by_name("Parent#initialize$Int32")
      parent_init.should_not be_nil
      parent_text = hir_text(parent_init.not_nil!)
      parent_text.should contain("GrandParent#initialize")
      parent_text.should_not contain("Parent#initialize(%0")
    end

    it "carries a qualified generic positional identity through late allocator rematerialization" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class Hash(K, V)
          def initialize
          end
        end

        class Set(T)
          getter marker : Int32

          def initialize(initial_capacity = nil)
            @marker = 7
          end

          protected def initialize(*, using_hash @hash : Hash(T, Nil))
            @marker = 99
          end

          def self.named
            ::Set(T).new(using_hash: Hash(T, Nil).new)
          end
        end

        module Builder
          def self.build
            ::Set(Int32).new
          end
        end

        Set(Int32).named
        Builder.build
      CRYSTAL

      allocator = converter.module.functions.find { |func| func.name.ends_with?("Set(Int32).new") }
      allocator.should_not be_nil

      owner = allocator.not_nil!.name.sub(/\.new$/, "")
      positional_name = "#{owner}#initialize$Nil"
      base_name = "#{owner}#initialize"
      arity_name = "#{owner}#initialize$arity1"
      named_name = "#{owner}#initialize$Hash(Int32, Nil)"

      unqualified_base = owner.starts_with?("::") ? owner.lchop("::") : owner
      converter.__test_allocator_initializer_def_name_for_base(
        "#{unqualified_base}#initialize",
        base_name,
        [Adamas::HIR::TypeRef::NIL],
      ).should eq(arity_name)
      converter.__test_allocator_initializer_def_name_for_base(
        "NoSuchSet#initialize",
        "NoSuchSet#initialize",
        [Adamas::HIR::TypeRef::NIL, Adamas::HIR::TypeRef::NIL],
      ).should be_nil

      converter.__test_lower_function_if_needed(named_name)
      named = converter.module.function_by_name(named_name)
      named.should_not be_nil
      hir_text(named.not_nil!).should contain("literal 99")

      # Force the generated allocator to take the late rematerialization path:
      # its body and the positional initializer body are both absent, while the
      # stale Completed state remains visible to lower_function_if_needed.
      converter.module.remove_function(allocator.not_nil!.name)
      converter.module.remove_function(positional_name) if converter.module.has_function?(positional_name)
      converter.__test_replace_initializer_params(owner, [] of {String, Adamas::HIR::TypeRef})
      converter.__test_mark_lowering_completed(base_name)
      converter.__test_regenerate_allocator(owner, [] of Adamas::HIR::TypeRef)

      regenerated = converter.module.function_by_name(allocator.not_nil!.name)
      regenerated.should_not be_nil
      calls = regenerated.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call).try do |call|
          call if call.method_name.includes?("Set(Int32)#initialize")
        end
      end
      calls.size.should eq(1)
      calls.first.not_nil!.method_name.should eq(arity_name)

      positional = converter.module.function_by_name(arity_name)
      positional.should_not be_nil
      hir_text(positional.not_nil!).should contain("literal 7")
      hir_text(positional.not_nil!).should_not contain("literal 99")

      named = converter.module.function_by_name(named_name)
      named.should_not be_nil
      hir_text(named.not_nil!).should contain("literal 99")
    end

    it "recovers generic initializer identity when parameter storage is erased" do
      converter = lower_source_backed_program_with_erased_generic_annotations(<<-CRYSTAL)
        class Hash(K, V)
        end

        class SetShape(T)
          getter marker : Int32

          def initialize(initial_capacity = nil)
            @marker = 7
          end

          protected def initialize(*, using_hash @hash : Hash(T, Nil))
            @marker = 99
          end
        end

        SetShape(Int32).new
        SetShape(Int32).new(4)
      CRYSTAL

      initialize_names = converter.__test_function_def_names("SetShape(Int32)#initialize")
      initialize_names.should contain("SetShape(Int32)#initialize$arity1")
      initialize_names.should contain("SetShape(Int32)#initialize$Hash(Int32, Nil)")

      allocator = converter.module.function_by_name("SetShape(Int32).new$Int32")
      allocator.should_not be_nil
      calls = allocator.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call).try { |call| call if call.method_name.includes?("SetShape(Int32)#initialize") }
      end
      calls.size.should eq(1)
      calls.first.not_nil!.method_name.should eq("SetShape(Int32)#initialize$Int32")
    end

    it "repairs a non-empty corrupted implicit-ivar annotation from source" do
      converter = lower_source_backed_program_with_corrupted_nonempty_annotation(<<-CRYSTAL)
        class Hash(K, V)
        end

        class SetShape(T)
          getter marker : Int32

          def initialize(initial_capacity = nil)
            @marker = 7
          end

          protected def initialize(*, using_hash @hash : Hash(T, Nil))
            @marker = 99
          end
        end

        SetShape(Int32).new
        SetShape(Int32).new(4)
      CRYSTAL

      initialize_names = converter.__test_function_def_names("SetShape(Int32)#initialize")
      initialize_names.should contain("SetShape(Int32)#initialize$arity1")
      initialize_names.should contain("SetShape(Int32)#initialize$Hash(Int32, Nil)")
      converter.__test_function_param_annotations("SetShape(Int32)#initialize$Hash(Int32, Nil)").should eq(
        [nil, "Hash(T, Nil)"]
      )

      converter.__test_lower_function_if_needed("SetShape(Int32)#initialize$arity1")
      converter.__test_lower_function_if_needed("SetShape(Int32)#initialize$Hash(Int32, Nil)")
      public_init = converter.module.function_by_name("SetShape(Int32)#initialize$Nil")
      named_init = converter.module.function_by_name("SetShape(Int32)#initialize$Hash(Int32, Nil)")
      public_init.should_not be_nil
      named_init.should_not be_nil
      public_text = hir_text(public_init.not_nil!)
      named_text = hir_text(named_init.not_nil!)
      public_text.should contain("literal 7")
      public_text.should_not contain("literal 99")
      named_text.should contain("literal 99")
      named_text.should_not contain("literal 7")

      allocator = converter.module.function_by_name("SetShape(Int32).new$Int32")
      allocator.should_not be_nil
      calls = allocator.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call).try { |call| call if call.method_name.includes?("SetShape(Int32)#initialize") }
      end
      calls.size.should eq(1)
      calls.first.not_nil!.method_name.should eq("SetShape(Int32)#initialize$Int32")
    end

    it "recovers lost implicit-ivar identity before typed allocator lookup" do
      converter = lower_source_backed_program_with_lost_nonempty_ivar_identity(<<-CRYSTAL)
        class Hash(K, V)
        end

        class SetShape(T)
          getter marker : Int32

          def initialize(initial_capacity = nil)
            @marker = 7
          end

          protected def initialize(*, using_hash @hash : Hash(T, Nil))
            @marker = 99
          end
        end

        SetShape(String).new(131072)
        SetShape(UInt32).new(131072)
      CRYSTAL

      initialize_names = converter.__test_function_def_names("SetShape(String)#initialize")
      initialize_names.should contain("SetShape(String)#initialize$arity1")

      # The phase-local RED is the stored protected DefNode itself: source
      # recovery must replace the corrupted non-empty placeholder with the
      # separator plus a typed implicit-ivar parameter before allocator lookup.
      protected_name = initialize_names.find do |name|
        name.includes?("$Hash(String, Nil)") || name.includes?("$arity1_named")
      end
      protected_name.should_not be_nil
      converter.__test_function_param_identity(protected_name.not_nil!).should eq([
        {nil, nil, nil, false, true, false},
        {"hash", "using_hash", "Hash(T, Nil)", true, false, false},
      ])
      initialize_names.should contain("SetShape(String)#initialize$Hash(String, Nil)")

      converter.__test_lower_function_if_needed("SetShape(String)#initialize$arity1")
      converter.__test_lower_function_if_needed("SetShape(String)#initialize$Hash(String, Nil)")
      public_init = converter.module.function_by_name("SetShape(String)#initialize$Nil")
      named_init = converter.module.function_by_name("SetShape(String)#initialize$Hash(String, Nil)")
      public_init.should_not be_nil
      named_init.should_not be_nil
      public_text = hir_text(public_init.not_nil!)
      named_text = hir_text(named_init.not_nil!)
      public_text.should contain("literal 7")
      public_text.should_not contain("literal 99")
      named_text.should contain("literal 99")
      named_text.should_not contain("literal 7")

      allocator = converter.module.function_by_name("SetShape(String).new$Int32")
      allocator.should_not be_nil
      calls = allocator.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call).try { |call| call if call.method_name.includes?("SetShape(String)#initialize") }
      end
      calls.size.should eq(1)
      calls.first.not_nil!.method_name.should eq("SetShape(String)#initialize$Int32")

      uint_allocator = converter.module.function_by_name("SetShape(UInt32).new$Int32")
      uint_allocator.should_not be_nil
      uint_calls = uint_allocator.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call).try { |call| call if call.method_name.includes?("SetShape(UInt32)#initialize") }
      end
      uint_calls.size.should eq(1)
      uint_calls.first.not_nil!.method_name.should eq("SetShape(UInt32)#initialize$Int32")
    end

    it "recovers a non-empty typed ordinary signature from its same-file source" do
      converter = lower_source_backed_program_with_lost_nonempty_typed_parameters(<<-CRYSTAL)
        class Slice(T)
        end

        class Array(T)
        end

        class Parameter
        end

        class OrdinaryShape
          def initialize(
            buffer : Slice(UInt8),
            params : Array(Parameter),
            tail : String? = nil,
            *,
            &block
          )
          end
        end
      CRYSTAL

      expected = ["Slice(UInt8)", "Array(Parameter)", "String?", nil, nil] of String?
      recovered_name = converter.__test_function_def_names("OrdinaryShape#initialize").find do |name|
        converter.__test_function_param_annotations(name) == expected
      end
      recovered_name.should_not be_nil
      converter.__test_function_param_identity(recovered_name.not_nil!).should eq([
        {"buffer", nil, "Slice(UInt8)", false, false, false},
        {"params", nil, "Array(Parameter)", false, false, false},
        {"tail", nil, "String?", false, false, false},
        {nil, nil, nil, false, true, false},
        {"block", nil, nil, false, false, true},
      ])
      converter.__test_function_param_default_presence(recovered_name.not_nil!).should eq(
        [false, false, true, false, false]
      )
    end

    it "recovers an anonymous typed block parameter from its same-file source" do
      code = <<-CRYSTAL
        def consume(& : String ->)
        end
      CRYSTAL
      arena, exprs = parse(code)
      corrupt_anonymous_typed_block_parameter(arena, exprs)
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => code})
      converter.arena = arena

      node = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode) }
        .find { |candidate| String.new(candidate.name) == "consume" }
      node.should_not be_nil
      recovered = converter.__test_source_recovered_def_for(node.not_nil!, arena)
      recovered.should_not be_nil
      recovered_params = recovered.not_nil!.params
      recovered_params.should_not be_nil
      recovered_params.not_nil!.size.should eq(1)
      recovered_param = recovered_params.not_nil!.first
      recovered_param.name.should be_nil
      recovered_param.is_block.should be_true
      recovered_param.type_annotation.should_not be_nil
      String.new(recovered_param.type_annotation.not_nil!).should eq("String ->")
    end

    it "splits and recovers an anonymous typed block after an ordinary parameter" do
      code = <<-CRYSTAL
        def consume(value : Int32, & : String, Int32, Float64 -> Bool)
        end
      CRYSTAL
      arena, exprs = parse(code)
      node = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode) }
        .find { |candidate| String.new(candidate.name) == "consume" }
      node.should_not be_nil
      params = node.not_nil!.params
      params.should_not be_nil
      params.not_nil!.size.should eq(2)
      params.not_nil!.pop

      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => code})
      recovered = converter.__test_source_recovered_def_for(node.not_nil!, arena)
      recovered.should_not be_nil
      recovered_params = recovered.not_nil!.params
      recovered_params.should_not be_nil
      recovered_params.not_nil!.size.should eq(2)
      recovered_block = recovered_params.not_nil!.last
      recovered_block.name.should be_nil
      recovered_block.is_block.should be_true
      recovered_block.type_annotation.should_not be_nil
      String.new(recovered_block.type_annotation.not_nil!).should eq("String, Int32, Float64 -> Bool")

      converter.__test_split_generic_type_args(
        "value : Int32, & : String, Int32, Float64 -> Bool"
      ).should eq([
        "value : Int32",
        "& : String, Int32, Float64 -> Bool",
      ])
      converter.__test_split_generic_type_args(
        "value : Hash(String, Array(Int32)), & : String, Int32, Float64 -> Bool"
      ).should eq([
        "value : Hash(String, Array(Int32))",
        "& : String, Int32, Float64 -> Bool",
      ])
      converter.__test_split_generic_type_args(
        "value : Int32, & : Hash(String, Array(Int32)), Tuple(Float64, Bool), String -> Bool"
      ).should eq([
        "value : Int32",
        "& : Hash(String, Array(Int32)), Tuple(Float64, Bool), String -> Bool",
      ])
      converter.__test_split_generic_type_args(
        "Hash(String, Array(Int32)), Tuple(Float64, Bool), String"
      ).should eq([
        "Hash(String, Array(Int32))",
        "Tuple(Float64, Bool)",
        "String",
      ])
    end

    it "recovers a stale scalar annotation even when its type span remains readable" do
      code = <<-CRYSTAL
        def consume(value : Int32)
        end
      CRYSTAL
      arena, exprs = parse(code)
      node = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode) }
        .find { |candidate| String.new(candidate.name) == "consume" }
      node.should_not be_nil
      params = node.not_nil!.params
      params.should_not be_nil
      original = params.not_nil!.first
      params.not_nil![0] = Adamas::Compiler::Frontend::Parameter.new(
        original.name,
        original.external_name,
        CORRUPTED_PARAMETER_TYPE_SOURCE.to_slice,
        original.default_value,
        original.span,
        original.name_span,
        original.external_name_span,
        original.type_span,
        original.default_span,
        original.is_splat,
        original.is_double_splat,
        original.is_block,
        original.is_instance_var,
      )

      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => code})
      recovered = converter.__test_source_recovered_def_for(node.not_nil!, arena)
      recovered.should_not be_nil
      recovered_param = recovered.not_nil!.params.not_nil!.first
      recovered_param.type_annotation.should_not be_nil
      String.new(recovered_param.type_annotation.not_nil!).should eq("Int32")
    end

    it "recovers a stale anonymous proc annotation even when its type span remains readable" do
      code = <<-CRYSTAL
        def consume(& : String ->)
        end
      CRYSTAL
      arena, exprs = parse(code)
      node = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode) }
        .find { |candidate| String.new(candidate.name) == "consume" }
      node.should_not be_nil
      params = node.not_nil!.params
      params.should_not be_nil
      original = params.not_nil!.first
      params.not_nil![0] = Adamas::Compiler::Frontend::Parameter.new(
        original.name,
        original.external_name,
        CORRUPTED_PARAMETER_TYPE_SOURCE.to_slice,
        original.default_value,
        original.span,
        original.name_span,
        original.external_name_span,
        original.type_span,
        original.default_span,
        original.is_splat,
        original.is_double_splat,
        original.is_block,
        original.is_instance_var,
      )

      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => code})
      recovered = converter.__test_source_recovered_def_for(node.not_nil!, arena)
      recovered.should_not be_nil
      recovered_param = recovered.not_nil!.params.not_nil!.first
      recovered_param.name.should be_nil
      recovered_param.is_block.should be_true
      recovered_param.type_annotation.should_not be_nil
      String.new(recovered_param.type_annotation.not_nil!).should eq("String ->")
    end

    it "does not source-recover from an arena with a conflicting direct extra source" do
      code = <<-CRYSTAL
        def consume(& : String ->)
        end
      CRYSTAL
      arena, exprs = parse(code)
      corrupt_anonymous_typed_block_parameter(arena, exprs)
      arena.retain_source("def generated(value : Int32)\nend\n")
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => code})

      node = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode) }
        .find { |candidate| String.new(candidate.name) == "consume" }
      node.should_not be_nil
      converter.__test_source_recovered_def_for(node.not_nil!, arena).should be_nil
    end

    it "recovers concrete and nullable metadata across a full constructor shape" do
      converter = lower_source_backed_program_with_lost_nonempty_typed_parameters(<<-CRYSTAL)
        class Span
        end

        class Slice(T)
        end

        class Array(T)
        end

        class Parameter
        end

        enum Visibility
          Public
        end

        class ReceiverCarrierShape
          def initialize(
            span : Span,
            name : Slice(UInt8),
            params : Array(Parameter),
            return_type : Slice(UInt8)?,
            body : Array(Int32)?,
            is_abstract : Bool? = nil,
            visibility : Visibility? = nil,
            receiver : String? = nil
          )
          end
        end
      CRYSTAL

      expected = [
        "Span",
        "Slice(UInt8)",
        "Array(Parameter)",
        "Slice(UInt8)?",
        "Array(Int32)?",
        "Bool?",
        "Visibility?",
        "String?",
      ] of String?
      recovered_name = converter.__test_function_def_names("ReceiverCarrierShape#initialize").find do |name|
        converter.__test_function_param_annotations(name) == expected
      end
      recovered_name.should_not be_nil
      converter.__test_function_param_default_presence(recovered_name.not_nil!).should eq(
        [false, false, false, false, false, true, true, true]
      )
    end

    it "recovers concrete metadata when the raw annotation payload is unreadable" do
      code = <<-CRYSTAL
        class Slice(T)
        end

        class Array(T)
        end

        class Parameter
        end

        class ReceiverCarrierUnreadable
          def initialize(
            name : Slice(UInt8),
            params : Array(Parameter),
            tail : String?
          )
          end
        end
      CRYSTAL
      arena, exprs = parse(code)
      replace_nonempty_typed_parameter_annotation_payload(arena, exprs)
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => code})
      converter.__test_safe_slice_to_string(unreadable_parameter_type_annotation).should be_nil
      node = find_initialize_def(arena, exprs)
      node.should_not be_nil
      recovered = converter.__test_source_recovered_def_for(node.not_nil!, arena)
      recovered.should_not be_nil
      recovered_params = recovered.not_nil!.params
      recovered_params.should_not be_nil
      recovered_params.not_nil!.map do |param|
        param.type_annotation.try { |slice| String.new(slice) }
      end.should eq(["Slice(UInt8)", "Array(Parameter)", "String?"] of String?)
    end

    it "preserves intact specialized parameter metadata against generic source" do
      code = <<-CRYSTAL
        class Pointer(T)
        end

        class GenericShape(T)
          def initialize(value : Pointer(T))
          end
        end
      CRYSTAL
      arena, exprs = parse(code)
      node = find_initialize_def(arena, exprs)
      node.should_not be_nil
      params = node.not_nil!.params
      params.should_not be_nil
      original = params.not_nil!.unsafe_fetch(0)
      original.type_annotation.should_not be_nil
      original.type_span.should_not be_nil
      params.not_nil![0] = Adamas::Compiler::Frontend::Parameter.new(
        original.name,
        original.external_name,
        "Pointer(UInt8)".to_slice,
        original.default_value,
        original.span,
        original.name_span,
        original.external_name_span,
        original.type_span,
        original.default_span,
        original.is_splat,
        original.is_double_splat,
        original.is_block,
        original.is_instance_var,
      )
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => code})
      converter.__test_source_recovered_def_for(node.not_nil!, arena).should be_nil
    end

    it "preserves specialized generic metadata when the raw annotation payload is unreadable" do
      code = <<-CRYSTAL
        class Pointer(T)
        end

        class GenericUnreadableShape(T)
          def initialize(value : Pointer(T))
          end
        end
      CRYSTAL
      arena, exprs = parse(code)
      replace_nonempty_typed_parameter_annotation_payload(arena, exprs)
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => code})
      class_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode) }
      class_nodes.each { |class_node| converter.register_class(class_node) }
      node = find_initialize_def(arena, exprs)
      node.should_not be_nil
      converter.__test_source_recovered_def_for_with_owner(
        node.not_nil!,
        arena,
        "GenericUnreadableShape(UInt8)"
      ).should be_nil
    end

    it "preserves unreadable specialized metadata for a qualified nested generic owner" do
      code = <<-CRYSTAL
        class Pointer(T)
        end

        module Outer
          class Box(T)
            def initialize(value : Pointer(T))
            end
          end
        end
      CRYSTAL
      arena, exprs = parse(code)
      replace_nonempty_typed_parameter_annotation_payload(arena, exprs)
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => code})
      pointer_node = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode) }
        .find { |class_node| String.new(class_node.name) == "Pointer" }
      outer_node = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::ModuleNode) }
        .find { |module_node| String.new(module_node.name) == "Outer" }
      pointer_node.should_not be_nil
      outer_node.should_not be_nil
      box_node = outer_node.not_nil!.body.not_nil!.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
      end.find { |class_node| String.new(class_node.name) == "Box" }
      box_node.should_not be_nil

      # Reproduce the self-host transport shape: the semantic nesting sidecar
      # knows `Outer -> Box`, while the generic template itself arrived under
      # its short source spelling rather than the qualified owner key.
      converter.seed_nested_type_names({"Outer" => Set{"Box"}})
      converter.register_class(pointer_node.not_nil!)
      converter.register_class(box_node.not_nil!)

      node = find_initialize_def(arena, exprs)
      node.should_not be_nil
      converter.__test_generic_owner_info_map("Outer::Box(UInt8)").should eq({"T" => "UInt8"})
      converter.__test_source_recovered_def_for_with_owner(
        node.not_nil!,
        arena,
        "Outer::Box(UInt8)"
      ).should be_nil
    end

    it "normalizes a root-qualified exact nested generic owner" do
      code = <<-CRYSTAL
        module Outer
          class Box(T)
          end
        end
      CRYSTAL
      arena, exprs = parse(code)
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => code})
      outer_node = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::ModuleNode) }
        .find { |module_node| String.new(module_node.name) == "Outer" }
      outer_node.should_not be_nil
      converter.register_module(outer_node.not_nil!)

      converter.__test_generic_owner_info_map("Outer::Box(UInt8)").should eq({"T" => "UInt8"})
      converter.__test_generic_owner_info_map("::Outer::Box(UInt8)").should eq({"T" => "UInt8"})
    end

    it "does not bind an ambiguous short generic template to a qualified owner" do
      code = <<-CRYSTAL
        module Outer
          class Box(T)
          end
        end
      CRYSTAL
      arena, exprs = parse(code)
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => code})
      outer_node = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::ModuleNode) }
        .find { |module_node| String.new(module_node.name) == "Outer" }
      outer_node.should_not be_nil
      box_node = outer_node.not_nil!.body.not_nil!.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
      end.find { |class_node| String.new(class_node.name) == "Box" }
      box_node.should_not be_nil

      converter.seed_nested_type_names({"Outer" => Set{"Box"}, "Other" => Set{"Box"}})
      converter.register_class(box_node.not_nil!)
      converter.__test_generic_owner_info_map("Outer::Box(UInt8)").should be_nil
    end

    it "does not source-recover a non-empty untyped signature" do
      code = <<-CRYSTAL
        class UntypedShape
          def initialize(buffer, params = nil)
          end
        end
      CRYSTAL
      arena, exprs = parse(code)
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => code})
      node = find_initialize_def(arena, exprs)
      node.should_not be_nil
      converter.__test_source_recovered_def_for(node.not_nil!, arena).should be_nil
    end

    it "does not source-recover when the arena has ambiguous extra sources" do
      code = <<-CRYSTAL
        class Slice(T)
        end

        class Array(T)
        end

        class Parameter
        end

        class AmbiguousShape
          def initialize(buffer : Slice(UInt8), params : Array(Parameter), tail : String?)
          end
        end
      CRYSTAL
      arena, exprs = parse(code)
      lose_nonempty_typed_parameter_metadata(arena, exprs)
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => code})
      converter.__test_store_extra_source(arena, "def generated(buffer : Nil)\nend\n")
      node = find_initialize_def(arena, exprs)
      node.should_not be_nil
      converter.__test_source_recovered_def_for(node.not_nil!, arena).should be_nil
    end

    it "recovers the complete generic initializer signature when parameter storage is empty" do
      converter = lower_source_backed_program_with_empty_initialize_params(<<-CRYSTAL)
        class Hash(K, V)
        end

        class SetShape(T)
          getter marker : Int32

          def initialize(initial_capacity = nil)
            @marker = 7
          end

          protected def initialize(*, using_hash @hash : Hash(T, Nil))
            @marker = 99
          end
        end

        SetShape(Int32).new
        SetShape(Int32).new(4)
      CRYSTAL

      initialize_names = converter.__test_function_def_names("SetShape(Int32)#initialize")
      initialize_names.should contain("SetShape(Int32)#initialize$arity1")
      initialize_names.should contain("SetShape(Int32)#initialize$Hash(Int32, Nil)")

      allocator = converter.module.function_by_name("SetShape(Int32).new$Int32")
      allocator.should_not be_nil
      calls = allocator.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call).try { |call| call if call.method_name.includes?("SetShape(Int32)#initialize") }
      end
      calls.size.should eq(1)
      calls.first.not_nil!.method_name.should eq("SetShape(Int32)#initialize$Int32")
    end

    it "does not invent parameters for a true zero-argument initializer" do
      converter = lower_source_backed_program_with_empty_initialize_params(<<-CRYSTAL)
        class ZeroShape
          getter marker : Int32

          def initialize()
            @marker = 1
          end
        end

        ZeroShape.new
      CRYSTAL

      names = converter.__test_function_def_names("ZeroShape#initialize")
      names.should contain("ZeroShape#initialize")
      names.any? { |name| name.includes?("$arity1") }.should be_false
    end

    it "recovers multiline nested generic defaults from the source signature" do
      converter = lower_source_backed_program_with_empty_initialize_params(<<-CRYSTAL)
        class Hash(K, V)
        end

        class NestedShape(T)
          getter marker : Int32

          def initialize(
            initial_capacity = nil,
          )
            @marker = 7
          end

          protected def initialize(
            *,
            using_hash @hash : Hash(Tuple(String, Int32), Nil)
          )
            @marker = 99
          end
        end

        NestedShape(Int32).new(nil)
      CRYSTAL

      names = converter.__test_function_def_names("NestedShape(Int32)#initialize")
      names.any? { |name| name.includes?("$arity1") }.should be_true
      names.should contain("NestedShape(Int32)#initialize$Hash(Tuple(String, Int32), Nil)")

      converter.__test_lower_function_if_needed("NestedShape(Int32)#initialize$Hash(Tuple(String, Int32), Nil)")
      public_init = converter.module.function_by_name("NestedShape(Int32)#initialize$Nil")
      named_init = converter.module.function_by_name("NestedShape(Int32)#initialize$Hash(Tuple(String, Int32), Nil)")
      public_init.should_not be_nil
      named_init.should_not be_nil
      public_text = hir_text(public_init.not_nil!)
      named_text = hir_text(named_init.not_nil!)
      public_text.should contain("literal 7")
      public_text.should_not contain("literal 99")
      named_text.should contain("literal 99")
      named_text.should_not contain("literal 7")
    end

    it "parses nested generic initializer annotations without trusting foreign spans" do
      code = <<-CRYSTAL
        def initialize(*, using_hash @hash : Hash(Tuple(String, Int32), Nil) = "a:b")
        end
      CRYSTAL
      arena, roots = parse(code)
      def_node = arena[roots.first].as(Adamas::Compiler::Frontend::DefNode)
      param = def_node.params.not_nil!.last
      erased = Adamas::Compiler::Frontend::Parameter.new(
        param.name,
        param.external_name,
        nil,
        param.default_value,
        param.span,
        param.name_span,
        param.external_name_span,
        nil,
        param.default_span,
        param.is_splat,
        param.is_double_splat,
        param.is_block,
        param.is_instance_var,
      )
      def_node.params.not_nil![-1] = erased

      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => code})
      converter.__test_parameter_type_annotation_from_source(erased, arena).should eq(
        "Hash(Tuple(String, Int32), Nil)"
      )

      converter.__test_store_extra_source(arena, "def initialize(*, using_hash @hash : Wrong)")
      converter.__test_parameter_type_annotation_from_source(erased, arena).should be_nil
    end
  end

  describe "parent overload lookup" do
    it "skips a nearer wrong-arity overload for an inherited bare call" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class BareRoot
          def render : String
            "root"
          end
        end

        class TypedParent < BareRoot
          def render(io : Int32) : String
            "typed"
          end
        end

        class BareChild < TypedParent
        end

        def render_child(child : BareChild) : String
          child.render
        end

        render_child(BareChild.new)
      CRYSTAL

      caller = converter.module.function_by_name("render_child$BareChild")
      caller.should_not be_nil
      calls = caller.not_nil!.blocks.flat_map(&.instructions)
        .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      render_call = calls.find { |call| call.method_name.includes?("#render") }
      render_call.should_not be_nil
      render_call.not_nil!.method_name.should_not contain("$Int32")

      inherited_target = converter.module.function_by_name(render_call.not_nil!.method_name)
      inherited_target.should_not be_nil
      inherited_target.not_nil!.params.size.should eq(1)
    end

    it "keeps inherited typed overload callsites specialized" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class Parent
          def read_bytes(type : UInt8, format : Int32) : UInt8
            type
          end

          def read_bytes(type : UInt64, format : Int32) : UInt64
            type
          end
        end

        class Child < Parent
        end

        def decode(io : Child)
          io.read_bytes(0_u8, 0).to_i
        end

        decode(Child.new)
      CRYSTAL

      func = converter.module.function_by_name("decode$Child")
      func.should_not be_nil

      text = hir_text(func.not_nil!)
      text.should contain("call %1.Parent#read_bytes$UInt8_Int32")
      text.should contain(": 7")
      text.should_not contain("Parent#read_bytes$UInt64_Int32")
      text.should_not contain(": 10")
    end

    it "does not reuse a base signature return type for later typed inherited calls" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class Parent
          def read_bytes(type, format : Int32)
            type
          end
        end

        class Child < Parent
        end

        def warm(io : Child)
          io.read_bytes(0_u64, 0)
        end

        def decode(io : Child)
          io.read_bytes(0_u8, 0).to_i
        end

        warm(Child.new)
        decode(Child.new)
      CRYSTAL

      func = converter.module.function_by_name("decode$Child")
      func.should_not be_nil

      text = hir_text(func.not_nil!)
      text.should contain("call %1.Parent#read_bytes$UInt8_Int32")
      text.should contain(": 7")
      text.should_not contain(": 10")
    end

    it "keeps virtual generic callsites on their exact typed return instead of the lowered base return" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class Parent
          def read_bytes(type, format : Int32)
            type
          end
        end

        class Child < Parent
        end

        def warm(io : Parent)
          io.read_bytes(0_u64, 0)
        end

        def decode(io : Parent)
          io.read_bytes(0_u16, 0).to_i
        end

        warm(Child.new)
        decode(Child.new)
      CRYSTAL

      func = converter.module.function_by_name("decode$Parent")
      func.should_not be_nil

      text = hir_text(func.not_nil!)
      text.should contain("Parent#read_bytes$UInt16_Int32")
      text.should contain(": 8 [virtual]")
      text.should_not contain(": 10 [virtual]")
    end
  end

  describe "missing concrete virtual target repair" do
    it "accepts a bare generic union restriction for concrete callsites" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class LayoutBox(T)
          getter size : Int32

          def initialize(@size : Int32)
          end
        end

        def union_size(value : LayoutBox | String) : Int32
          value.size
        end

        union_size(LayoutBox(Int32).new(11))
        union_size("xy")
      CRYSTAL

      call_names = converter.module.functions.select { |func| func.name.includes?("union_size") }
        .flat_map(&.blocks)
        .flat_map(&.instructions)
        .compact_map(&.as?(Adamas::HIR::Call))
        .map(&.method_name)
      call_names.should contain("LayoutBox | String#size")
    end

    it "rejects a runtime return union containing a bare generic template" do
      expect_raises(Adamas::HIR::LoweringError, /can't use LayoutBox\(T\) in unions yet/) do
        lower_program_with_main(<<-CRYSTAL)
          class LayoutBox(T)
            getter size : Int32

            def initialize(@size : Int32)
            end
          end

          def dynamic_value(flag : Bool) : LayoutBox | String
            flag ? LayoutBox(Int32).new(11) : "xy"
          end

          dynamic_value(true)
        CRYSTAL
      end
    end

    it "rejects a nullable runtime return containing a bare generic template" do
      expect_raises(Adamas::HIR::LoweringError, /can't use LayoutBox\(T\) in unions yet/) do
        lower_program_with_main(<<-CRYSTAL)
          class LayoutBox(T)
            getter size : Int32

            def initialize(@size : Int32)
            end
          end

          def dynamic_value(flag : Bool) : LayoutBox?
            flag ? LayoutBox(Int32).new(11) : nil
          end

          dynamic_value(true)
        CRYSTAL
      end
    end

    it "dispatches a bare generic receiver across layout-distinct instances" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class LayoutBox(T)
          getter payload : T
          getter size : Int32

          def initialize(@payload : T, @size : Int32)
          end
        end

        def erased_size(value : LayoutBox) : Int32
          value.size
        end

        erased_size(LayoutBox(Int32).new(1, 11))
        erased_size(LayoutBox(String).new("x", 22))
      CRYSTAL
      converter.flush_pending_functions

      caller = converter.module.function_by_name("erased_size$LayoutBox")
      caller.should_not be_nil
      size_call = caller.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end.find { |call| call.method_name == "LayoutBox#size" }
      size_call.should_not be_nil
      size_call.not_nil!.virtual.should be_true
      size_call.not_nil!.type.should eq(Adamas::HIR::TypeRef::INT32)

      converter.module.has_function_with_body?("LayoutBox#size").should be_false
      int_getter = converter.module.function_by_name("LayoutBox(Int32)#size")
      string_getter = converter.module.function_by_name("LayoutBox(String)#size")
      int_getter.should_not be_nil
      string_getter.should_not be_nil
      converter.module.has_function_with_body?("LayoutBox(Int32)#size").should be_true
      converter.module.has_function_with_body?("LayoutBox(String)#size").should be_true

      int_field = int_getter.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::FieldGet)
      end.find { |field| field.field_name == "@size" }
      string_field = string_getter.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::FieldGet)
      end.find { |field| field.field_name == "@size" }
      int_field.should_not be_nil
      string_field.should_not be_nil
      int_field.not_nil!.field_offset.should_not eq(string_field.not_nil!.field_offset)
    end

    it "preserves instance-dependent returns for a concrete generic receiver union" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class LayoutBox(T)
          getter payload : T

          def initialize(@payload : T)
          end

          def tagged_payload(_tag : Int32) : T
            @payload
          end

          def untyped_payload(_tag) : T
            @payload
          end
        end

        def choose_box(flag : Bool) : LayoutBox(Int32) | LayoutBox(String)
          flag ? LayoutBox(Int32).new(7) : LayoutBox(String).new("x")
        end

        def erased_payload(value : LayoutBox(Int32) | LayoutBox(String))
          value.payload
        end

        def erased_tagged_payload(value : LayoutBox(Int32) | LayoutBox(String))
          value.tagged_payload(0)
        end

        def erased_untyped_payload(value : LayoutBox(Int32) | LayoutBox(String))
          value.untyped_payload(0)
        end

        def erased_nilable_payload(value : LayoutBox(Nil) | LayoutBox(String))
          value.payload
        end

        erased_payload(choose_box(true))
        erased_tagged_payload(choose_box(false))
        erased_untyped_payload(choose_box(true))
        erased_nilable_payload(LayoutBox(Nil).new(nil))
      CRYSTAL
      converter.flush_pending_functions

      caller = converter.module.functions.find { |function| function.name.starts_with?("erased_payload$") }
      caller.should_not be_nil
      converter.__test_get_type_name_from_ref(caller.not_nil!.return_type).should eq("Int32 | String")

      payload_call = caller.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end.find { |call| call.method_name.ends_with?("#payload") }
      payload_call.should_not be_nil
      payload_call.not_nil!.virtual.should be_true
      converter.__test_get_type_name_from_ref(payload_call.not_nil!.type).should eq("Int32 | String")

      int_payload = converter.module.function_by_name("LayoutBox(Int32)#payload")
      string_payload = converter.module.function_by_name("LayoutBox(String)#payload")
      nil_payload = converter.module.function_by_name("LayoutBox(Nil)#payload")
      int_payload.should_not be_nil
      string_payload.should_not be_nil
      nil_payload.should_not be_nil
      converter.__test_get_type_name_from_ref(int_payload.not_nil!.return_type).should eq("Int32")
      converter.__test_get_type_name_from_ref(string_payload.not_nil!.return_type).should eq("String")
      converter.__test_get_type_name_from_ref(nil_payload.not_nil!.return_type).should eq("Nil")
      converter.module.has_function_with_body?("LayoutBox(Int32)#payload").should be_true
      converter.module.has_function_with_body?("LayoutBox(String)#payload").should be_true
      converter.module.has_function_with_body?("LayoutBox(Nil)#payload").should be_true

      tagged_caller = converter.module.functions.find { |function| function.name.starts_with?("erased_tagged_payload$") }
      tagged_caller.should_not be_nil
      converter.__test_get_type_name_from_ref(tagged_caller.not_nil!.return_type).should eq("Int32 | String")

      tagged_payload_call = tagged_caller.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end.find { |call| call.method_name.includes?("#tagged_payload") }
      tagged_payload_call.should_not be_nil
      tagged_payload_call.not_nil!.virtual.should be_true
      converter.__test_get_type_name_from_ref(tagged_payload_call.not_nil!.type).should eq("Int32 | String")

      untyped_caller = converter.module.functions.find { |function| function.name.starts_with?("erased_untyped_payload$") }
      untyped_caller.should_not be_nil
      converter.__test_get_type_name_from_ref(untyped_caller.not_nil!.return_type).should eq("Int32 | String")

      untyped_payload_call = untyped_caller.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end.find { |call| call.method_name.includes?("#untyped_payload") }
      untyped_payload_call.should_not be_nil
      untyped_payload_call.not_nil!.virtual.should be_true
      converter.__test_get_type_name_from_ref(untyped_payload_call.not_nil!.type).should eq("Int32 | String")

      nilable_caller = converter.module.functions.find { |function| function.name.starts_with?("erased_nilable_payload$") }
      nilable_caller.should_not be_nil
      converter.__test_get_type_name_from_ref(nilable_caller.not_nil!.return_type).should eq("Nil | String")

      nilable_payload_call = nilable_caller.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end.find { |call| call.method_name.ends_with?("#payload") }
      nilable_payload_call.should_not be_nil
      converter.__test_get_type_name_from_ref(nilable_payload_call.not_nil!.type).should eq("Nil | String")
    end

    it "preserves the inherited zero-argument hash ABI for mixed generic value unions" do
      converter = lower_program_with_main(<<-CRYSTAL, source_path: "/tmp/inherited_pointer_hash.cr", stdlib_root: File.expand_path("src/stdlib"))
        module Crystal
          struct Hasher
          end
        end

        class Object
          def hash(hasher : Crystal::Hasher) : Crystal::Hasher
            hasher
          end

          def hash
            0_u64
          end
        end

        def erased_hash(value : Pointer(Void) | Tuple(String, Int32))
          value.hash
        end

        erased_hash(Pointer(Void).null)
      CRYSTAL
      converter.flush_pending_functions

      caller = converter.module.functions.find { |function| function.name.starts_with?("erased_hash$") }
      caller.should_not be_nil
      converter.__test_get_type_name_from_ref(caller.not_nil!.return_type).should eq("UInt64")

      hash_calls = caller.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end.select { |call| call.method_name.includes?("#hash") }
      hash_calls.should_not be_empty
      hash_calls.each do |call|
        converter.__test_get_type_name_from_ref(call.type).should eq("UInt64")
      end
      protocol_return = converter.__test_get_function_return_type_for_call(
        "Pointer(Void)#hash$Crystal::Hasher",
        1,
      )
      converter.__test_get_type_name_from_ref(protocol_return).should eq("Crystal::Hasher")
      pointer_template_return = converter.__test_get_function_return_type_for_call("Pointer#hash", 0)
      converter.__test_get_type_name_from_ref(pointer_template_return).should eq("UInt64")
    end

    it "materializes unannotated typed hash branches inside generic block lowering" do
      converter = lower_program_with_main(<<-CRYSTAL)
        module Crystal
          struct Hasher
          end
        end

        struct Int32
          def hash(hasher)
            hasher
          end
        end

        struct Pointer(T)
          def hash(hasher)
            hasher
          end
        end

        struct HashBox(T)
          def initialize(@value : T)
          end

          def each(&block : T ->)
            yield @value
          end

          def hash(hasher : Crystal::Hasher)
            each do |element|
              hasher = element.hash(hasher)
            end
            hasher
          end
        end

        HashBox(Int32 | Pointer(UInt8)).new(1).hash(Crystal::Hasher.new)
      CRYSTAL
      converter.flush_pending_functions

      %w(Int32 Pointer(UInt8)).each do |owner|
        target = converter.module.function_by_name("#{owner}#hash$Crystal::Hasher")
        target.should_not be_nil
        converter.__test_get_type_name_from_ref(target.not_nil!.return_type).should eq("Crystal::Hasher")
      end

      block_function = converter.module.functions.find do |function|
        function.name.starts_with?("__crystal_block_proc_")
      end
      block_function.should_not be_nil
      hash_calls = block_function.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end.select { |call| call.method_name.includes?("#hash") }
      hash_calls.size.should eq(2)
      hash_calls.each do |call|
        converter.__test_get_type_name_from_ref(call.type).should eq("Crystal::Hasher")
      end
    end

    it "does not infer a typed hash ABI from an external parameter name" do
      converter = lower_program_with_main(
        <<-CRYSTAL,
          module Crystal
            struct Hasher
            end
          end

          class ExternalHash
            def hash(hasher)
              hasher
            end
          end

          0
        CRYSTAL
        source_path: "/tmp/external_hash_parameter_name.cr",
        stdlib_root: File.expand_path("src/stdlib"),
      )

      names = converter.__test_function_def_names
      names.should contain("ExternalHash#hash$arity1")
      names.should_not contain("ExternalHash#hash$Crystal::Hasher")
    end

    it "preserves the inherited zero-argument hash ABI for semantic type tuples" do
      stdlib_root = File.expand_path("src/stdlib")
      converter = lower_program_with_main(<<-CRYSTAL, source_path: File.join(stdlib_root, "semantic_type_hash.cr"), stdlib_root: stdlib_root)
        module Crystal
          struct Hasher
          end
        end

        class Object
          def hash(hasher : Crystal::Hasher) : Crystal::Hasher
            hasher
          end

          def hash
            0_u64
          end
        end

        module Adamas
          module Compiler
            module Semantic
              abstract class Type
                def hash : UInt64
                  1_u64
                end
              end
            end
          end
        end

        def semantic_type_hash(
          value : Pointer(Void) | Tuple(String, Adamas::Compiler::Semantic::Type),
        )
          value.hash
        end

        semantic_type_hash(Pointer(Void).null)
      CRYSTAL
      converter.flush_pending_functions

      caller = converter.module.functions.find { |function| function.name.starts_with?("semantic_type_hash$") }
      caller.should_not be_nil
      converter.__test_get_type_name_from_ref(caller.not_nil!.return_type).should eq("UInt64")

      hash_calls = caller.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end.select { |call| call.method_name.includes?("#hash") }
      hash_calls.should_not be_empty
      hash_calls.each do |call|
        converter.__test_get_type_name_from_ref(call.type).should eq("UInt64")
      end
    end

    it "certifies an exact inherited Object hash target for a built-in value branch" do
      stdlib_root = File.expand_path("src/stdlib")
      converter = lower_program_with_main(<<-CRYSTAL, source_path: File.join(stdlib_root, "object_hash_contract.cr"), stdlib_root: stdlib_root)
        class Object
          def hash : UInt64
            0_u64
          end
        end

        0
      CRYSTAL

      converter.module.has_function_with_body?("Object#hash").should be_false
      return_type = converter.__test_concrete_union_dispatch_return_type(
        "Object#hash",
        "Pointer(Void)",
        "hash",
        0,
      )
      converter.__test_get_type_name_from_ref(return_type).should eq("UInt64")
    end

    it "does not certify an untrusted or shadowed inherited Object hash target" do
      untrusted = lower_program_with_main(<<-CRYSTAL)
        class Object
          def hash : UInt64
            0_u64
          end
        end

        0
      CRYSTAL

      untrusted.module.has_function_with_body?("Object#hash").should be_false
      untrusted.__test_concrete_union_dispatch_return_type(
        "Object#hash",
        "Tuple(String, Int32)",
        "hash",
        0,
      ).should eq(Adamas::HIR::TypeRef::VOID)

      stdlib_root = File.expand_path("src/stdlib")
      shadowed = lower_program_with_main(<<-CRYSTAL, source_path: File.join(stdlib_root, "shadowed_object_hash.cr"), stdlib_root: stdlib_root)
        class Object
          def hash : UInt64
            0_u64
          end
        end

        struct Pointer(T)
          def hash(seed : Int32 = 0) : String
            "pointer"
          end
        end

        0
      CRYSTAL

      shadowed.__test_concrete_union_dispatch_return_type(
        "Object#hash",
        "Pointer(Void)",
        "hash",
        0,
      ).should eq(Adamas::HIR::TypeRef::VOID)
    end

    it "preserves the typed hash protocol ABI for nilable Tuple unions" do
      source = <<-CRYSTAL
        module Crystal
          struct Hasher
            def nil
              self
            end
          end
        end

        struct Nil
          def hash(hasher)
            hasher.nil
          end
        end

        struct Tuple
          def hash(hasher)
            hasher
          end
        end

        def append_hash(
          value : Nil | Tuple(String, Int32),
          hasher : Crystal::Hasher,
        )
          value.hash(hasher)
        end

        append_hash(nil, Crystal::Hasher.new)
      CRYSTAL
      converter = lower_program_with_main(
        source,
        source_path: File.expand_path("src/stdlib/hash_contract_spec.cr"),
        stdlib_root: File.expand_path("src/stdlib"),
      )
      converter.flush_pending_functions

      caller = converter.module.functions.find { |function| function.name.starts_with?("append_hash$") }
      caller.should_not be_nil
      caller_name = caller.not_nil!.name
      tuple_target = "Tuple(String, Int32)#hash$Crystal::Hasher"
      converter.module.remove_function(caller_name).should be_true
      converter.module.remove_function(tuple_target).should be_true
      converter.__test_reset_lowering_state(caller_name)
      converter.__test_reset_lowering_state(tuple_target)

      # Re-lower the caller with the concrete Tuple protocol target absent.
      # The exact stdlib ABI certificate is sufficient for the caller; the
      # ordinary pending queue may materialize the target body afterward.
      converter.__test_lower_function_if_needed(caller_name)
      caller = converter.module.function_by_name(caller_name)
      caller.should_not be_nil
      converter.__test_get_type_name_from_ref(caller.not_nil!.return_type).should eq("Crystal::Hasher")

      hash_calls = caller.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end.select { |call| call.method_name.includes?("#hash") }
      hash_calls.should_not be_empty
      hash_calls.each do |call|
        converter.__test_get_type_name_from_ref(call.type).should eq("Crystal::Hasher")
      end
      converter.module.has_function_with_body?(tuple_target).should be_false
      converter.flush_pending_functions
      converter.module.has_function_with_body?(tuple_target).should be_true
    end

    it "preserves stdlib typed hash returns across mixed Bool and Tuple unions" do
      source = <<-CRYSTAL
        module Crystal
          struct Hasher
            def bool(value)
              self
            end
          end
        end

        struct Bool
          def hash(hasher)
            hasher.bool(self)
          end
        end

        struct Tuple
          def hash(hasher)
            hasher
          end
        end

        def append_hash(
          value : Bool | Tuple(String, Int32),
          hasher : Crystal::Hasher,
        )
          value.hash(hasher)
        end

        append_hash(false, Crystal::Hasher.new)
      CRYSTAL
      converter = lower_program_with_main(
        source,
        source_path: File.expand_path("src/stdlib/hash_contract_spec.cr"),
        stdlib_root: File.expand_path("src/stdlib"),
      )
      converter.flush_pending_functions

      caller = converter.module.functions.find { |function| function.name.starts_with?("append_hash$") }
      caller.should_not be_nil
      converter.__test_get_type_name_from_ref(caller.not_nil!.return_type).should eq("Crystal::Hasher")

      hash_calls = caller.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end.select { |call| call.method_name.includes?("#hash") }
      hash_calls.size.should eq(2)
      hash_calls.each do |call|
        call.method_name.ends_with?("$Crystal::Hasher").should be_true
        converter.__test_get_type_name_from_ref(call.type).should eq("Crystal::Hasher")
      end
    end

    it "preserves recursive stdlib typed hash protocol returns before body inference" do
      source = <<-CRYSTAL
        module Crystal
          struct Hasher
            def bool(value)
              value.hash(self)
            end
          end
        end

        struct Bool
          def hash(hasher)
            hasher.bool(self)
          end
        end
      CRYSTAL
      converter = lower_program_with_main(
        source,
        source_path: File.expand_path("src/stdlib/bool.cr"),
        stdlib_root: File.expand_path("src/stdlib"),
      )

      contract = converter.__test_canonical_typed_hash_return_contract(
        "Bool#hash$Crystal::Hasher",
        "Bool",
      )
      contract.should_not be_nil
      converter.__test_get_type_name_from_ref(contract.not_nil!).should eq("Crystal::Hasher")

      return_type = converter.__test_get_function_return_type_for_call(
        "Bool#hash$Crystal::Hasher",
        1,
      )
      converter.__test_get_type_name_from_ref(return_type).should eq("Crystal::Hasher")

      external = lower_program_with_main(
        <<-CRYSTAL,
          module Crystal
            struct Hasher
            end
          end

          struct Bool
            def hash(hasher : Crystal::Hasher)
              "external"
            end
          end
        CRYSTAL
        source_path: File.expand_path("src/stdlib_evil/bool.cr"),
        stdlib_root: File.expand_path("src/stdlib"),
      )
      external.__test_canonical_typed_hash_return_contract(
        "Bool#hash$Crystal::Hasher",
        "Bool",
      ).should be_nil
      external_return = external.__test_get_function_return_type_for_call(
        "Bool#hash$Crystal::Hasher",
        1,
      )
      external.__test_get_type_name_from_ref(external_return).should eq("String")
    end

    it "does not certify a macro-generated typed hash by macro source path" do
      stdlib_root = File.expand_path("src/stdlib")
      converter = lower_program_with_sources(
        <<-CRYSTAL,
          module Crystal
            struct Hasher
            end
          end

          macro define_bad_hash
            def hash(hasher)
              "bad"
            end
          end

          class ExternalHash
            define_bad_hash()
          end
        CRYSTAL
        source_path: File.join(stdlib_root, "object.cr"),
        stdlib_root: stdlib_root,
      )

      target = "ExternalHash#hash$Crystal::Hasher"
      converter.__test_canonical_typed_hash_return_contract(
        target,
        "ExternalHash",
      ).should be_nil
      return_type = converter.__test_get_function_return_type_for_call(target, 1)
      converter.__test_get_type_name_from_ref(return_type).should eq("String")
    end

    it "does not certify a generated source snapshot by inherited stdlib path" do
      stdlib_root = File.expand_path("src/stdlib")
      source_path = File.join(stdlib_root, "object.cr")
      origin_arena, _ = parse(File.read(source_path))
      generated_source = <<-CRYSTAL
        module Crystal
          struct Hasher
          end
        end

        class ExternalHash
          def hash(hasher)
            "bad"
          end
        end
      CRYSTAL

      converter = lower_program_with_sources(
        generated_source,
        source_path: source_path,
        stdlib_root: stdlib_root,
      )
      converter.bootstrap_bind_main_arenas([origin_arena])

      target = "ExternalHash#hash$Crystal::Hasher"
      converter.__test_canonical_typed_hash_return_contract(
        target,
        "ExternalHash",
      ).should be_nil
      return_type = converter.__test_get_function_return_type_for_call(target, 1)
      converter.__test_get_type_name_from_ref(return_type).should eq("String")
    end

    it "keeps a materialized Tuple hash override authoritative" do
      expect_raises(
        Adamas::HIR::LoweringError,
        /heterogeneous hash returns/,
      ) do
        converter = lower_program_with_main(<<-CRYSTAL)
          module Crystal
            struct Hasher
            end
          end

          struct Nil
            def hash(hasher : Crystal::Hasher) : Crystal::Hasher
              hasher
            end
          end

          struct Tuple
            def hash(hasher : Crystal::Hasher) : String
              "custom"
            end
          end

          def append_hash(
            value : Nil | Tuple(String, Int32),
            hasher : Crystal::Hasher,
          )
            value.hash(hasher)
          end

          append_hash(nil, Crystal::Hasher.new)
        CRYSTAL
        converter.flush_pending_functions
      end
    end

    it "rejects a bodyless explicit Tuple hash ABI conflict" do
      converter = lower_program_with_main(<<-CRYSTAL, source_path: "/tmp/typed_hash_override.cr", stdlib_root: File.expand_path("src/stdlib"))
        module Crystal
          struct Hasher
          end
        end

        struct Tuple
          def hash(hasher : Crystal::Hasher) : String
            "custom"
          end
        end
      CRYSTAL

      target = "Tuple(String, Int32)#hash$Crystal::Hasher"
      contract_return = converter.__test_concrete_union_dispatch_return_type(
        target,
        "Tuple(String, Int32)",
        "hash",
        1,
      )
      contract_return.should eq(Adamas::HIR::TypeRef::VOID)
    end

    it "does not certify a bodyless unannotated Tuple hash override" do
      converter = lower_program_with_main(<<-CRYSTAL, source_path: "/tmp/bodyless_hash_override.cr", stdlib_root: File.expand_path("src/stdlib"))
        module Crystal
          struct Hasher
          end
        end

        struct Tuple
          def hash(hasher : Crystal::Hasher)
            "custom"
          end
        end
      CRYSTAL

      target = "Tuple(String, Int32)#hash$Crystal::Hasher"
      contract_return = converter.__test_concrete_union_dispatch_return_type(
        target,
        "Tuple(String, Int32)",
        "hash",
        1,
      )
      contract_return.should eq(Adamas::HIR::TypeRef::VOID)

      resolved_return = converter.__test_get_function_return_type_for_call(target, 1)
      resolved_return.should eq(Adamas::HIR::TypeRef::STRING)
    end

    it "does not bypass a concrete Tuple hash(hasher) override" do
      converter = lower_program_with_main(<<-CRYSTAL, source_path: "/tmp/typed_hash_override.cr", stdlib_root: File.expand_path("src/stdlib"))
        module Crystal
          struct Hasher
          end
        end

        struct Tuple
          def hash(hasher : Crystal::Hasher) : String
            "custom"
          end
        end

        def custom_tuple_hash(
          value : Tuple(String, Int32),
          hasher : Crystal::Hasher,
        )
          value.hash(hasher)
        end

        custom_tuple_hash({"value", 1}, Crystal::Hasher.new)
      CRYSTAL
      converter.flush_pending_functions

      caller = converter.module.functions.find do |function|
        function.name.starts_with?("custom_tuple_hash$")
      end
      caller.should_not be_nil
      converter.__test_get_type_name_from_ref(caller.not_nil!.return_type).should eq("String")
    end

    it "does not bypass a concrete zero-argument Tuple hash override" do
      converter = lower_program_with_main(<<-CRYSTAL, source_path: "/tmp/zero_hash_override.cr", stdlib_root: File.expand_path("src/stdlib"))
        struct Tuple
          def hash : String
            "custom"
          end
        end

        def custom_tuple_hash(value : Tuple(String, Int32))
          value.hash
        end

        custom_tuple_hash({"value", 1})
      CRYSTAL
      converter.flush_pending_functions

      caller = converter.module.functions.find do |function|
        function.name.starts_with?("custom_tuple_hash$")
      end
      caller.should_not be_nil
      converter.__test_get_type_name_from_ref(caller.not_nil!.return_type).should eq("String")
    end

    it "does not certify an external typed Pointer hash override" do
      converter = lower_program_with_main(<<-CRYSTAL, source_path: "/tmp/pointer_hash_override.cr", stdlib_root: File.expand_path("src/stdlib"))
        module Crystal
          struct Hasher
          end
        end

        struct Pointer(T)
          def hash(hasher : Crystal::Hasher) : String
            "pointer"
          end
        end
      CRYSTAL

      target = "Pointer(Void)#hash$Crystal::Hasher"
      contract_return = converter.__test_concrete_union_dispatch_return_type(
        target,
        "Pointer(Void)",
        "hash",
        1,
      )
      contract_return.should eq(Adamas::HIR::TypeRef::VOID)

      resolved_return = converter.__test_get_function_return_type_for_call(target, 1)
      converter.__test_get_type_name_from_ref(resolved_return).should eq("String")
    end

    it "certifies only stdlib macro-generated Pointer hash contracts" do
      stdlib_root = File.expand_path("src/stdlib")
      source = <<-CRYSTAL
        module Crystal
          struct Hasher
          end
        end

        macro define_pointer_hash
          def hash(hasher)
            hasher
          end
        end

        struct Pointer(T)
          define_pointer_hash
        end

        def append_pointer_hash(value : Pointer(Void), hasher : Crystal::Hasher)
          value.hash(hasher)
        end

        append_pointer_hash(Pointer(Void).null, Crystal::Hasher.new)
      CRYSTAL

      trusted = lower_program_with_sources(
        source,
        source_path: File.join(stdlib_root, "pointer_hash_contract_spec.cr"),
        stdlib_root: stdlib_root,
      )
      trusted_contract = trusted.__test_canonical_typed_hash_return_contract(
        "Pointer(Void)#hash$Crystal::Hasher",
        "Pointer(Void)",
      )
      trusted_contract.should_not be_nil
      trusted.__test_get_type_name_from_ref(trusted_contract.not_nil!).should eq("Crystal::Hasher")

      external = lower_program_with_sources(
        source.sub("hasher\n          end", "\"external\"\n          end"),
        source_path: "/tmp/external_pointer_hash_macro.cr",
        stdlib_root: stdlib_root,
      )
      external.__test_canonical_typed_hash_return_contract(
        "Pointer(Void)#hash$Crystal::Hasher",
        "Pointer(Void)",
      ).should be_nil
    end

    it "keeps the stdlib Pointer hash contract across unrelated external reopenings" do
      stdlib_root = File.expand_path("src/stdlib")
      trusted_source = <<-CRYSTAL
        module Crystal
          struct Hasher
          end
        end

        macro define_pointer_hash
          def hash(hasher)
            hasher
          end
        end

        struct Pointer(T)
          define_pointer_hash
        end

        def append_pointer_hash(value : Pointer(Void), hasher : Crystal::Hasher)
          value.hash(hasher)
        end

        append_pointer_hash(Pointer(Void).null, Crystal::Hasher.new)
      CRYSTAL
      external_source = <<-CRYSTAL
        struct Pointer(T)
          def unrelated
            1
          end
        end
      CRYSTAL
      trusted_arena, trusted_exprs = parse(trusted_source)
      external_arena, external_exprs = parse(external_source)
      converter = Adamas::HIR::AstToHir.new(
        trusted_arena,
        main_arenas: [trusted_arena, external_arena] of Adamas::Compiler::Frontend::ArenaLike,
        sources_by_arena: {
          trusted_arena.object_id.to_u64  => trusted_source,
          external_arena.object_id.to_u64 => external_source,
        },
        paths_by_arena: {
          trusted_arena.object_id.to_u64  => File.join(stdlib_root, "pointer_hash_contract_spec.cr"),
          external_arena.object_id.to_u64 => "/tmp/unrelated_pointer_reopening.cr",
        },
        stdlib_root: stdlib_root,
      )

      converter.arena = trusted_arena
      trusted_exprs.compact_map { |id| trusted_arena[id].as?(Adamas::Compiler::Frontend::ModuleNode) }
        .each { |node| converter.register_module(node) }
      trusted_exprs.compact_map { |id| trusted_arena[id].as?(Adamas::Compiler::Frontend::MacroDefNode) }
        .each { |node| converter.register_macro(node) }
      trusted_exprs.compact_map { |id| trusted_arena[id].as?(Adamas::Compiler::Frontend::ClassNode) }
        .each { |node| converter.register_class(node) }
      converter.arena = external_arena
      external_exprs.compact_map { |id| external_arena[id].as?(Adamas::Compiler::Frontend::ClassNode) }
        .each { |node| converter.register_class(node) }
      converter.arena = trusted_arena
      main_exprs = trusted_exprs.compact_map do |id|
        id.index.to_u64 if trusted_arena[id].is_a?(Adamas::Compiler::Frontend::CallNode)
      end
      converter.lower_main(main_exprs)

      contract = converter.__test_canonical_typed_hash_return_contract(
        "Pointer(Void)#hash$Crystal::Hasher",
        "Pointer(Void)",
      )
      contract.should_not be_nil
      converter.__test_get_type_name_from_ref(contract.not_nil!).should eq("Crystal::Hasher")
    end

    it "does not certify an unresolved external Pointer hash macro reopening" do
      stdlib_root = File.expand_path("src/stdlib")
      trusted_source = <<-CRYSTAL
        module Crystal
          struct Hasher
          end
        end

        macro define_trusted_pointer_hash
          def hash(hasher)
            hasher
          end
        end

        struct Pointer(T)
          define_trusted_pointer_hash
        end
      CRYSTAL
      external_source = <<-CRYSTAL
        macro define_external_pointer_hash
          def hash(hasher)
            "external"
          end
        end

        struct Pointer(T)
          define_external_pointer_hash
        end
      CRYSTAL
      trusted_arena, trusted_exprs = parse(trusted_source)
      external_arena, external_exprs = parse(external_source)
      converter = Adamas::HIR::AstToHir.new(
        trusted_arena,
        main_arenas: [trusted_arena, external_arena] of Adamas::Compiler::Frontend::ArenaLike,
        sources_by_arena: {
          trusted_arena.object_id.to_u64  => trusted_source,
          external_arena.object_id.to_u64 => external_source,
        },
        paths_by_arena: {
          trusted_arena.object_id.to_u64  => File.join(stdlib_root, "pointer_hash_contract_spec.cr"),
          external_arena.object_id.to_u64 => "/tmp/external_pointer_hash_macro_reopening.cr",
        },
        stdlib_root: stdlib_root,
      )

      converter.arena = trusted_arena
      trusted_exprs.compact_map { |id| trusted_arena[id].as?(Adamas::Compiler::Frontend::ModuleNode) }
        .each { |node| converter.register_module(node) }
      trusted_exprs.compact_map { |id| trusted_arena[id].as?(Adamas::Compiler::Frontend::MacroDefNode) }
        .each { |node| converter.register_macro(node) }
      trusted_exprs.compact_map { |id| trusted_arena[id].as?(Adamas::Compiler::Frontend::ClassNode) }
        .each { |node| converter.register_class(node) }
      converter.arena = external_arena
      external_exprs.compact_map { |id| external_arena[id].as?(Adamas::Compiler::Frontend::MacroDefNode) }
        .each { |node| converter.register_macro(node) }
      external_exprs.compact_map { |id| external_arena[id].as?(Adamas::Compiler::Frontend::ClassNode) }
        .each { |node| converter.register_class(node) }

      converter.__test_canonical_typed_hash_return_contract(
        "Pointer(Void)#hash$Crystal::Hasher",
        "Pointer(Void)",
      ).should be_nil
    end

    it "does not certify an unresolved external Pointer hash include" do
      stdlib_root = File.expand_path("src/stdlib")
      trusted_source = <<-CRYSTAL
        module Crystal
          struct Hasher
          end
        end

        macro define_trusted_pointer_hash
          def hash(hasher)
            hasher
          end
        end

        struct Pointer(T)
          define_trusted_pointer_hash
        end
      CRYSTAL
      external_source = <<-CRYSTAL
        module ExternalPointerHash
          macro included
            def hash(hasher)
              "external"
            end
          end
        end

        struct Pointer(T)
          include ExternalPointerHash
        end
      CRYSTAL
      trusted_arena, trusted_exprs = parse(trusted_source)
      external_arena, external_exprs = parse(external_source)
      converter = Adamas::HIR::AstToHir.new(
        trusted_arena,
        main_arenas: [trusted_arena, external_arena] of Adamas::Compiler::Frontend::ArenaLike,
        sources_by_arena: {
          trusted_arena.object_id.to_u64  => trusted_source,
          external_arena.object_id.to_u64 => external_source,
        },
        paths_by_arena: {
          trusted_arena.object_id.to_u64  => File.join(stdlib_root, "pointer_hash_contract_spec.cr"),
          external_arena.object_id.to_u64 => "/tmp/external_pointer_hash_include.cr",
        },
        stdlib_root: stdlib_root,
      )

      converter.arena = trusted_arena
      trusted_exprs.compact_map { |id| trusted_arena[id].as?(Adamas::Compiler::Frontend::ModuleNode) }
        .each { |node| converter.register_module(node) }
      trusted_exprs.compact_map { |id| trusted_arena[id].as?(Adamas::Compiler::Frontend::MacroDefNode) }
        .each { |node| converter.register_macro(node) }
      trusted_exprs.compact_map { |id| trusted_arena[id].as?(Adamas::Compiler::Frontend::ClassNode) }
        .each { |node| converter.register_class(node) }
      converter.arena = external_arena
      external_exprs.compact_map { |id| external_arena[id].as?(Adamas::Compiler::Frontend::ModuleNode) }
        .each { |node| converter.register_module(node) }
      external_exprs.compact_map { |id| external_arena[id].as?(Adamas::Compiler::Frontend::ClassNode) }
        .each { |node| converter.register_class(node) }

      converter.__test_canonical_typed_hash_return_contract(
        "Pointer(Void)#hash$Crystal::Hasher",
        "Pointer(Void)",
      ).should be_nil
    end

    it "preserves an explicit zero-argument Pointer hash override" do
      converter = lower_program_with_main(<<-CRYSTAL)
        struct Pointer(T)
          def hash : String
            "pointer"
          end
        end

        def pointer_hash(value : Pointer(Void))
          value.hash
        end

        pointer_hash(Pointer(Void).null)
      CRYSTAL
      converter.flush_pending_functions

      caller = converter.module.functions.find { |function| function.name.starts_with?("pointer_hash$") }
      caller.should_not be_nil
      converter.__test_get_type_name_from_ref(caller.not_nil!.return_type).should eq("String")
    end

    it "rejects custom zero-argument hash overrides that disagree with built-in union branches" do
      expect_raises(
        Adamas::HIR::LoweringError,
        /heterogeneous hash returns/,
      ) do
        converter = lower_program_with_main(<<-CRYSTAL)
          module Crystal
            struct Hasher
            end
          end

          class Object
            def hash : UInt64
              0_u64
            end
          end

          class CustomHash
            def hash : String
              "custom"
            end
          end

          def erased_hash(value : CustomHash | Pointer(Void) | Tuple(String, Int32))
            value.hash
          end

          erased_hash(Pointer(Void).null)
        CRYSTAL
        converter.flush_pending_functions
      end
    end

    it "rejects typed hash protocol branches with different return ABIs" do
      expect_raises(
        Adamas::HIR::LoweringError,
        /heterogeneous hash returns/,
      ) do
        converter = lower_program_with_main(<<-CRYSTAL)
          module Crystal
            struct Hasher
            end
          end

          class Object
            def hash(hasher : Crystal::Hasher) : Crystal::Hasher
              hasher
            end
          end

          class CustomHash
            def hash(hasher : Crystal::Hasher) : String
              "custom"
            end
          end

          def append_hash(
            value : CustomHash | Pointer(Void) | Tuple(String, Int32),
            hasher : Crystal::Hasher,
          )
            value.hash(hasher)
          end

          append_hash(Pointer(Void).null, Crystal::Hasher.new)
        CRYSTAL
        converter.flush_pending_functions
      end
    end

    it "preserves instance-dependent returns for a tagged concrete generic struct union" do
      converter = lower_program_with_main(<<-CRYSTAL)
        struct EntryLike(K, V)
          getter value : V

          def initialize(@key : K, @value : V)
          end
        end

        def entry_value(entry : EntryLike(String, Nil | String) | EntryLike(String, Nil) | EntryLike(String, String))
          entry.value
        end

        entry_value(EntryLike(String, String).new("key", "value"))
      CRYSTAL
      converter.flush_pending_functions

      caller = converter.module.functions.find { |function| function.name.starts_with?("entry_value$") }
      caller.should_not be_nil
      converter.__test_get_type_name_from_ref(caller.not_nil!.return_type).should eq("Nil | String")

      value_call = caller.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end.find { |call| call.method_name.ends_with?("#value") }
      value_call.should_not be_nil
      value_call.not_nil!.virtual.should be_false
      converter.__test_get_type_name_from_ref(value_call.not_nil!.type).should eq("Nil | String")

      mixed_value = converter.module.function_by_name("EntryLike(String, Nil | String)#value")
      nil_value = converter.module.function_by_name("EntryLike(String, Nil)#value")
      string_value = converter.module.function_by_name("EntryLike(String, String)#value")
      mixed_value.should_not be_nil
      nil_value.should_not be_nil
      string_value.should_not be_nil
      converter.__test_get_type_name_from_ref(mixed_value.not_nil!.return_type).should eq("Nil | String")
      converter.__test_get_type_name_from_ref(nil_value.not_nil!.return_type).should eq("Nil")
      converter.__test_get_type_name_from_ref(string_value.not_nil!.return_type).should eq("String")
    end

    it "wraps concrete branch returns for a heterogeneous generic struct union" do
      converter = lower_program_with_main(<<-CRYSTAL)
        struct DispatchHandler
          getter tag : Int32

          def initialize(@tag : Int32)
          end
        end

        struct DispatchBox(T)
          getter payload : T

          def initialize(@payload : T)
          end
        end

        def dispatched_payload(value : DispatchBox(DispatchHandler) | DispatchBox(Proc(Int32, Nil)))
          value.payload
        end

        dispatched_payload(DispatchBox(DispatchHandler).new(DispatchHandler.new(7)))
      CRYSTAL
      converter.flush_pending_functions

      caller = converter.module.functions.find { |function| function.name.starts_with?("dispatched_payload$") }
      caller.should_not be_nil
      caller = caller.not_nil!
      result_type_name = converter.__test_get_type_name_from_ref(caller.return_type)
      result_type_name.should contain("DispatchHandler")
      result_type_name.should contain("Proc")

      instructions = caller.blocks.flat_map(&.instructions)
      payload_calls = instructions.compact_map(&.as?(Adamas::HIR::Call))
        .select { |call| call.method_name.ends_with?("#payload") }
      payload_calls.size.should eq(2)
      payload_calls.map { |call| converter.__test_get_type_name_from_ref(call.type) }.sort
        .should eq(["DispatchHandler", "Proc"])
      handler_call = payload_calls.find do |call|
        converter.__test_get_type_name_from_ref(call.type) == "DispatchHandler"
      end
      handler_call.should_not be_nil
      converter.module.get_type_descriptor(handler_call.not_nil!.type).not_nil!.kind
        .should eq(Adamas::HIR::TypeKind::Struct)
      handler_info = converter.class_info.values.find do |info|
        info.type_ref == handler_call.not_nil!.type
      end
      handler_info.should_not be_nil
      handler_info.not_nil!.is_struct.should be_true

      wraps = instructions.compact_map(&.as?(Adamas::HIR::UnionWrap))
      wraps_by_value = wraps.to_h { |wrap| {wrap.value, wrap} }
      payload_calls.each do |call|
        wrap = wraps_by_value[call.id]?
        wrap.should_not be_nil
        wrap = wrap.not_nil!
        wrap.type.should eq(caller.return_type)
        wrap.variant_type_id.should be >= 0
      end

      result_phi = instructions.compact_map(&.as?(Adamas::HIR::Phi))
        .find { |phi| phi.type == caller.return_type }
      result_phi.should_not be_nil
      result_phi.not_nil!.incoming.each do |(_, value_id)|
        wraps.any? { |wrap| wrap.id == value_id }.should be_true
      end
    end

    it "rejects incompatible return carriers for a same-template generic struct union" do
      expect_raises(Adamas::HIR::LoweringError, /heterogeneous returns for unsupported concrete generic receiver union/) do
        lower_program_with_main(<<-CRYSTAL)
          struct ValueBox(T)
            def initialize(@payload : T)
            end

            def tagged_payload(_tag : Int32) : T
              @payload
            end
          end

          def erased_payload(value : ValueBox(Int32) | ValueBox(String))
            value.tagged_payload(0)
          end

          erased_payload(ValueBox(Int32).new(7))
        CRYSTAL
      end
    end

    it "rejects scalar and Proc returns from a same-template generic struct union" do
      expect_raises(Adamas::HIR::LoweringError, /heterogeneous returns for unsupported concrete generic receiver union/) do
        lower_program_with_main(<<-CRYSTAL)
          struct ScalarProcBox(T)
            getter payload : T

            def initialize(@payload : T)
            end
          end

          def erased_payload(value : ScalarProcBox(Int32) | ScalarProcBox(Proc(Int32, Nil)))
            value.payload
          end

          erased_payload(ScalarProcBox(Int32).new(7))
        CRYSTAL
      end
    end

    it "rejects C struct and Proc returns from a same-template generic struct union" do
      expect_raises(Adamas::HIR::LoweringError, /heterogeneous returns for unsupported concrete generic receiver union/) do
        lower_program_with_main(<<-CRYSTAL)
          lib ForeignTypes
            struct Pair
              value : Int32
            end
          end

          struct ForeignProcBox(T)
            getter payload : T

            def initialize(@payload : T)
            end
          end

          def erased_payload(value : ForeignProcBox(ForeignTypes::Pair) | ForeignProcBox(Proc(Int32, Nil)))
            value.payload
          end

          erased_payload(ForeignProcBox(ForeignTypes::Pair).new(ForeignTypes::Pair.new))
        CRYSTAL
      end
    end

    it "rejects multiple non-nil header variants for a generic struct return union" do
      expect_raises(Adamas::HIR::LoweringError, /heterogeneous returns for unsupported concrete generic receiver union/) do
        lower_program_with_main(<<-CRYSTAL)
          class LeftRef
          end

          class RightRef
          end

          struct PolyBox(T)
            getter payload : T

            def initialize(@payload : T)
            end
          end

          def erased_payload(value : PolyBox(Nil) | PolyBox(LeftRef) | PolyBox(RightRef))
            value.payload
          end

          erased_payload(PolyBox(LeftRef).new(LeftRef.new))
        CRYSTAL
      end
    end

    it "rejects heterogeneous returns outside the registered generic dispatch corridor" do
      expect_raises(Adamas::HIR::LoweringError, /heterogeneous returns for unsupported concrete generic receiver union/) do
        lower_program_with_main(<<-CRYSTAL)
          class LeftBox(T)
            getter payload : T

            def initialize(@payload : T)
            end
          end

          class RightBox(T)
            getter payload : T

            def initialize(@payload : T)
            end
          end

          def erased_payload(value : LeftBox(Int32) | RightBox(String))
            value.payload
          end

          erased_payload(LeftBox(Int32).new(7))
        CRYSTAL
      end

      expect_raises(Adamas::HIR::LoweringError, /heterogeneous returns for unsupported concrete generic receiver union/) do
        lower_program_with_main(<<-CRYSTAL)
          struct LeftValueBox(T)
            def initialize(@payload : T)
            end

            def tagged_payload(_tag : Int32) : T
              @payload
            end
          end

          struct RightValueBox(T)
            def initialize(@payload : T)
            end

            def tagged_payload(_tag : Int32) : T
              @payload
            end
          end

          def erased_payload(value : LeftValueBox(Int32) | RightValueBox(String))
            value.tagged_payload(0)
          end

          erased_payload(LeftValueBox(Int32).new(7))
        CRYSTAL
      end
    end

    it "preserves valid nil returns for a registered reference-generic union" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class LogBox(T)
          def log
          end
        end

        def erased_log(value : LogBox(Int32) | LogBox(String))
          value.log
        end

        erased_log(LogBox(Int32).new)
      CRYSTAL
      converter.flush_pending_functions

      caller = converter.module.functions.find { |function| function.name.starts_with?("erased_log$") }
      caller.should_not be_nil
      log_call = caller.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end.find { |call| call.method_name.ends_with?("#log") }
      log_call.should_not be_nil
      log_call.not_nil!.virtual.should be_true
      log_call.not_nil!.type.should eq(Adamas::HIR::TypeRef::NIL)
    end

    it "preserves instance-dependent returns for builtin reference-generic unions" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class Array(T)
          getter payload : T

          def initialize(@payload : T)
          end
        end

        def erased_payload(value : Array(Int32) | Array(String))
          value.payload
        end

        erased_payload(Array(Int32).new(7))
        erased_payload(Array(String).new("x"))
      CRYSTAL
      converter.flush_pending_functions

      caller = converter.module.functions.find { |function| function.name.starts_with?("erased_payload$") }
      caller.should_not be_nil
      converter.__test_get_type_name_from_ref(caller.not_nil!.return_type).should eq("Int32 | String")

      payload_call = caller.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end.find { |call| call.method_name.ends_with?("#payload") }
      payload_call.should_not be_nil
      payload_call.not_nil!.virtual.should be_true
      converter.__test_get_type_name_from_ref(payload_call.not_nil!.type).should eq("Int32 | String")
    end

    it "rejects explicit arguments without one shared concrete generic union formal ABI" do
      expect_raises(Adamas::HIR::LoweringError, /incompatible explicit arguments for concrete generic receiver union/) do
        lower_program_with_main(<<-CRYSTAL)
          class ParamBox(T)
            def take(value : T) : Int32
              1
            end
          end

          def choose_box(flag : Bool) : ParamBox(Int32) | ParamBox(String)
            flag ? ParamBox(Int32).new : ParamBox(String).new
          end

          def erased_take(value : ParamBox(Int32) | ParamBox(String))
            value.take(1)
          end

          erased_take(choose_box(false))
        CRYSTAL
      end

      expect_raises(Adamas::HIR::LoweringError, /incompatible explicit arguments for concrete generic receiver union/) do
        lower_program_with_main(<<-CRYSTAL)
          class NilableParamBox(T)
            def take(value : T) : Int32
              1
            end
          end

          def choose_nilable_box(flag : Bool) : NilableParamBox(Int32 | Nil) | NilableParamBox(String | Nil)
            flag ? NilableParamBox(Int32 | Nil).new : NilableParamBox(String | Nil).new
          end

          def erased_nilable_take(value : NilableParamBox(Int32 | Nil) | NilableParamBox(String | Nil))
            value.take(nil)
          end

          NilableParamBox(Int32 | Nil).new.take(nil)
          NilableParamBox(String | Nil).new.take(nil)
          erased_nilable_take(choose_nilable_box(false))
        CRYSTAL
      end

      expect_raises(Adamas::HIR::LoweringError, /incompatible explicit arguments for concrete generic receiver union/) do
        lower_program_with_main(<<-CRYSTAL)
          class NumericParamBox(T)
            def take(value : T) : Int32
              1
            end
          end

          def choose_numeric_box(flag : Bool) : NumericParamBox(Int32) | NumericParamBox(UInt32)
            flag ? NumericParamBox(Int32).new : NumericParamBox(UInt32).new
          end

          def erased_numeric_take(value : NumericParamBox(Int32) | NumericParamBox(UInt32))
            value.take(1)
          end

          erased_numeric_take(choose_numeric_box(false))
        CRYSTAL
      end

      expect_raises(Adamas::HIR::LoweringError, /incompatible explicit arguments for concrete generic receiver union/) do
        lower_program_with_main(<<-CRYSTAL)
          class OverlapParamBox(T)
            def take(value : T) : Int32
              1
            end
          end

          def choose_overlap_box(flag : Bool) : OverlapParamBox(Int32 | Int64) | OverlapParamBox(Int32 | UInt32)
            flag ? OverlapParamBox(Int32 | Int64).new : OverlapParamBox(Int32 | UInt32).new
          end

          def erased_overlap_take(value : OverlapParamBox(Int32 | Int64) | OverlapParamBox(Int32 | UInt32))
            value.take(1)
          end

          erased_overlap_take(choose_overlap_box(false))
        CRYSTAL
      end
    end

    it "accepts a shared explicit ABI from a transitively included module" do
      converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
        module SharedExplicitAbi(T)
          def accept(value : T) : String
            "generic"
          end
        end

        module ForwardSharedExplicitAbi(T)
          include SharedExplicitAbi(T)

          def accept(value : String) : String
            value
          end
        end

        class SharedExplicitAbiBox(T)
          include ForwardSharedExplicitAbi(T)
        end

        def choose_shared_explicit_abi_box(flag : Bool) : SharedExplicitAbiBox(Int32) | SharedExplicitAbiBox(String)
          flag ? SharedExplicitAbiBox(Int32).new : SharedExplicitAbiBox(String).new
        end

        def use_shared_explicit_abi(value : SharedExplicitAbiBox(Int32) | SharedExplicitAbiBox(String))
          value.accept("ok")
        end

        use_shared_explicit_abi(choose_shared_explicit_abi_box(false))
      CRYSTAL
      converter.flush_pending_functions

      caller = converter.module.functions.find { |function| function.name.starts_with?("use_shared_explicit_abi$") }
      caller.should_not be_nil
      call = caller.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end.find { |instruction| instruction.method_name.includes?("#accept") }
      call.should_not be_nil
      call.not_nil!.virtual.should be_true
      call.not_nil!.type.should eq(Adamas::HIR::TypeRef::STRING)
    end

    it "specializes included-module explicit ABIs for each generic union variant" do
      converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
        module SharedMappedExplicitAbi(T)
          def accept(value : T) : String
            value
          end
        end

        class SharedMappedExplicitAbiBox(Tag, Value)
          include SharedMappedExplicitAbi(Value)
        end

        def choose_shared_mapped_explicit_abi_box(flag : Bool) : SharedMappedExplicitAbiBox(Int32, String) | SharedMappedExplicitAbiBox(Bool, String)
          flag ? SharedMappedExplicitAbiBox(Int32, String).new : SharedMappedExplicitAbiBox(Bool, String).new
        end

        def use_shared_mapped_explicit_abi(value : SharedMappedExplicitAbiBox(Int32, String) | SharedMappedExplicitAbiBox(Bool, String))
          value.accept("ok")
        end

        use_shared_mapped_explicit_abi(choose_shared_mapped_explicit_abi_box(false))
      CRYSTAL
      converter.flush_pending_functions

      caller = converter.module.functions.find { |function| function.name.starts_with?("use_shared_mapped_explicit_abi$") }
      caller.should_not be_nil
      call = caller.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end.find { |instruction| instruction.method_name.includes?("#accept") }
      call.should_not be_nil
      call.not_nil!.virtual.should be_true
      call.not_nil!.type.should eq(Adamas::HIR::TypeRef::STRING)
    end

    it "rejects incompatible included-module explicit ABIs for generic union variants" do
      expect_raises(Adamas::HIR::LoweringError, /incompatible explicit arguments for concrete generic receiver union/) do
        lower_program_with_main(<<-CRYSTAL, source_backed: true)
          module IncompatibleMappedExplicitAbi(T)
            def accept(value : T) : String
              value.to_s
            end
          end

          class IncompatibleMappedExplicitAbiBox(T)
            include IncompatibleMappedExplicitAbi(T)
          end

          def choose_incompatible_mapped_explicit_abi_box(flag : Bool) : IncompatibleMappedExplicitAbiBox(Int32) | IncompatibleMappedExplicitAbiBox(String)
            flag ? IncompatibleMappedExplicitAbiBox(Int32).new : IncompatibleMappedExplicitAbiBox(String).new
          end

          def use_incompatible_mapped_explicit_abi(value : IncompatibleMappedExplicitAbiBox(Int32) | IncompatibleMappedExplicitAbiBox(String))
            value.accept(1)
          end

          use_incompatible_mapped_explicit_abi(choose_incompatible_mapped_explicit_abi_box(false))
        CRYSTAL
      end
    end

    it "keeps compatible included-module explicit ABIs for concrete generic receivers" do
      converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
        module CompatibleConcreteMappedExplicitAbi(T)
          def accept(value : T) : String
            value.to_s
          end
        end

        class CompatibleConcreteMappedExplicitAbiBox(T)
          include CompatibleConcreteMappedExplicitAbi(T)
        end

        CompatibleConcreteMappedExplicitAbiBox(String).new.accept("ok")
      CRYSTAL

      main = converter.module.function_by_name("__adamas_main")
      main.should_not be_nil
      hir_text(main.not_nil!).should contain("CompatibleConcreteMappedExplicitAbiBox(String)#accept$String")
    end

    it "selects a compatible overload from the authoritative included module" do
      converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
        module OverloadedConcreteExplicitAbi(T)
          def accept(value : String) : String
            value
          end

          def accept(value : Int32) : String
            value.to_s
          end
        end

        class OverloadedConcreteExplicitAbiBox(T)
          include OverloadedConcreteExplicitAbi(T)
        end

        OverloadedConcreteExplicitAbiBox(String).new.accept(1)
      CRYSTAL

      main = converter.module.function_by_name("__adamas_main")
      main.should_not be_nil
      hir_text(main.not_nil!).should contain("OverloadedConcreteExplicitAbiBox(String)#accept$Int32")
    end

    it "consumes a semantic overload target before legacy HIR scoring" do
      source = <<-CRYSTAL
        class SemanticRoute
          def route(value : String) : Int32
            1
          end

          def route(value : Int32) : Int32
            2
          end
        end

        SemanticRoute.new.route(1)
      CRYSTAL

      legacy = lower_program_with_main(source, profile_call_resolution: true)
      semantic = lower_program_with_main(
        source,
        semantic_call_targets: true,
        profile_call_resolution: true,
      )

      legacy.__test_call_resolution_profile_count.should eq(
        semantic.__test_call_resolution_profile_count + 1
      )
      main = semantic.module.function_by_name("__adamas_main")
      main.should_not be_nil
      hir_text(main.not_nil!).should contain("SemanticRoute#route$Int32")
    end

    it "does not replace an exact semantic recursive target with a sibling overload" do
      # Without the semantic-authority guard this keeps the same emitted name
      # while silently replacing the selected DefNode with the untyped sibling.
      converter = lower_program_with_main(<<-CRYSTAL, semantic_call_targets: true)
        class SemanticRecursiveRoute
          def route(value) : String
            "wrong"
          end

          def route(value : Int32)
            self.route(value)
          end
        end

        SemanticRecursiveRoute.new.route(1)
      CRYSTAL

      recursive = converter.module.function_by_name("SemanticRecursiveRoute#route$Int32")
      recursive.should_not be_nil
      text = hir_text(recursive.not_nil!)
      text.should contain("SemanticRecursiveRoute#route$Int32")
      text.should_not contain("wrong")
    end

    it "scores authoritative included-module overloads before comparing union ABIs" do
      converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
        module ScoredUnionExplicitAbi(T)
          def accept(value : T) : String
            value.to_s
          end

          def accept(value : Int32) : String
            value.to_s
          end
        end

        class ScoredUnionExplicitAbiBox(T)
          include ScoredUnionExplicitAbi(T)
        end

        def choose_scored_union_explicit_abi_box(flag : Bool) : ScoredUnionExplicitAbiBox(UInt32) | ScoredUnionExplicitAbiBox(Int32)
          flag ? ScoredUnionExplicitAbiBox(UInt32).new : ScoredUnionExplicitAbiBox(Int32).new
        end

        def use_scored_union_explicit_abi(value : ScoredUnionExplicitAbiBox(UInt32) | ScoredUnionExplicitAbiBox(Int32))
          value.accept(1)
        end

        use_scored_union_explicit_abi(choose_scored_union_explicit_abi_box(false))
      CRYSTAL
      converter.flush_pending_functions

      caller = converter.module.functions.find { |function| function.name.starts_with?("use_scored_union_explicit_abi$") }
      caller.should_not be_nil
      call = caller.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end.find { |instruction| instruction.method_name.includes?("#accept") }
      call.should_not be_nil
      call.not_nil!.virtual.should be_true
      call.not_nil!.type.should eq(Adamas::HIR::TypeRef::STRING)
    end

    it "prefers a direct concrete generic declaration over an included module" do
      converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
        module ShadowedConcreteExplicitAbi(T)
          def accept(value : T) : String
            value.to_s
          end
        end

        class DirectConcreteExplicitAbiBox(T)
          include ShadowedConcreteExplicitAbi(T)

          def accept(value : Int32) : String
            value.to_s
          end
        end

        DirectConcreteExplicitAbiBox(String).new.accept(1)
      CRYSTAL

      main = converter.module.function_by_name("__adamas_main")
      main.should_not be_nil
      hir_text(main.not_nil!).should contain("DirectConcreteExplicitAbiBox(String)#accept$Int32")
    end

    it "keeps a direct untyped generic method authoritative over an included typed peer" do
      converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
        module IncludedTypedAuthority(T)
          def marker(value : String) : Int32
            99
          end
        end

        class DirectUntypedAuthorityBox(T)
          include IncludedTypedAuthority(T)

          def marker(value) : Int32
            7
          end
        end

        DirectUntypedAuthorityBox(String).new.marker("value")
      CRYSTAL
      converter.flush_pending_functions

      main = converter.module.function_by_name("__adamas_main")
      main.should_not be_nil
      hir_text(main.not_nil!).should contain("DirectUntypedAuthorityBox(String)#marker$String")

      target = converter.module.functions.find do |function|
        function.name == "DirectUntypedAuthorityBox(String)#marker$String"
      end
      target.should_not be_nil
      text = hir_text(target.not_nil!)
      text.should contain("literal 7")
      text.should_not contain("literal 99")
    end

    it "selects an included typed overload when the direct generic overload is incompatible" do
      converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
        module IncludedCompatibleOverload(T)
          def marker(value : T) : Int32
            99
          end
        end

        class DirectIncompatibleOverloadBox(T)
          include IncludedCompatibleOverload(T)

          def marker(value : String) : Int32
            7
          end
        end

        DirectIncompatibleOverloadBox(Int32).new.marker(1)
        DirectIncompatibleOverloadBox(Int32).new.marker("value")
      CRYSTAL
      converter.flush_pending_functions

      main = converter.module.function_by_name("__adamas_main")
      main.should_not be_nil
      hir_text(main.not_nil!).should contain("DirectIncompatibleOverloadBox(Int32)#marker$Int32")
      hir_text(main.not_nil!).should contain("DirectIncompatibleOverloadBox(Int32)#marker$String")

      target = converter.module.functions.find do |function|
        function.name == "DirectIncompatibleOverloadBox(Int32)#marker$Int32"
      end
      target.should_not be_nil
      text = hir_text(target.not_nil!)
      text.should contain("literal 99")
      text.should_not contain("literal 7")

      direct = converter.module.functions.find do |function|
        function.name == "DirectIncompatibleOverloadBox(Int32)#marker$String"
      end
      direct.should_not be_nil
      direct_text = hir_text(direct.not_nil!)
      direct_text.should contain("literal 7")
      direct_text.should_not contain("literal 99")
    end

    it "continues to a later included origin after an incompatible sibling" do
      converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
        module FirstIncompatibleSiblingOverload
          def marker(value : Bool) : Int32
            11
          end
        end

        module LaterCompatibleSiblingOverload
          def marker(value : Int32) : Int32
            22
          end
        end

        class MultipleIncludedOverloadBox(T)
          include FirstIncompatibleSiblingOverload
          include LaterCompatibleSiblingOverload

          def marker(value : String) : Int32
            7
          end
        end

        MultipleIncludedOverloadBox(String).new.marker(1)
      CRYSTAL
      converter.flush_pending_functions

      target = converter.module.functions.find do |function|
        function.name == "MultipleIncludedOverloadBox(String)#marker$Int32"
      end
      target.should_not be_nil
      text = hir_text(target.not_nil!)
      text.should contain("literal 22")
      text.should_not contain("literal 11")
      text.should_not contain("literal 7")
    end

    it "does not treat included-module defaults as explicit call arguments" do
      lower_program_with_main(<<-CRYSTAL, source_backed: true)
        module DefaultedConcreteExplicitAbi(T)
          def accept(value : T = "default") : String
            value.to_s
          end
        end

        class DefaultedConcreteExplicitAbiBox(T)
          include DefaultedConcreteExplicitAbi(T)
        end

        DefaultedConcreteExplicitAbiBox(String).new.accept
      CRYSTAL
    end

    it "rejects incompatible included-module explicit ABIs for concrete generic receivers" do
      expect_raises(Adamas::HIR::LoweringError, /incompatible explicit arguments for concrete generic receiver/) do
        lower_program_with_main(<<-CRYSTAL, source_backed: true)
          module ConcreteMappedExplicitAbi(T)
            def accept(value : T) : String
              value.to_s
            end
          end

          class ConcreteMappedExplicitAbiBox(T)
            include ConcreteMappedExplicitAbi(T)
          end

          ConcreteMappedExplicitAbiBox(String).new.accept(1)
        CRYSTAL
      end
    end

    it "does not authorize an included-module origin with a later compatible signature" do
      expect_raises(Adamas::HIR::LoweringError, /incompatible explicit arguments for concrete generic receiver/) do
        lower_program_with_main(<<-CRYSTAL, source_backed: true)
          module LaterCompatibleExplicitAbi
            def accept(value : Int32) : String
              value.to_s
            end
          end

          module FirstIncompatibleExplicitAbi(T)
            include LaterCompatibleExplicitAbi

            def accept(value : T) : String
              value.to_s
            end
          end

          class OriginOrderedExplicitAbiBox(T)
            include FirstIncompatibleExplicitAbi(T)
          end

          OriginOrderedExplicitAbiBox(String).new.accept(1)
        CRYSTAL
      end
    end

    it "accepts compatible normalized included-module call shapes for concrete generic receivers" do
      lower_program_with_main(<<-CRYSTAL, source_backed: true)
        module CompatibleNormalizedConcreteExplicitAbi(T)
          def accept(value : T) : String
            value.to_s
          end
        end

        class CompatibleNormalizedConcreteExplicitAbiBox(T)
          include CompatibleNormalizedConcreteExplicitAbi(T)
        end

        CompatibleNormalizedConcreteExplicitAbiBox(String).new.accept(value: "named")
        CompatibleNormalizedConcreteExplicitAbiBox(String).new.accept(*{"splat"})
      CRYSTAL
    end

    it "rejects incompatible normalized included-module call shapes for concrete generic receivers" do
      error_pattern = /incompatible explicit arguments for concrete generic receiver/

      expect_raises(Adamas::HIR::LoweringError, error_pattern) do
        lower_program_with_main(<<-CRYSTAL, source_backed: true)
          module NamedConcreteMappedExplicitAbi(T)
            def accept(value : T) : String
              value.to_s
            end
          end

          class NamedConcreteMappedExplicitAbiBox(T)
            include NamedConcreteMappedExplicitAbi(T)
          end

          NamedConcreteMappedExplicitAbiBox(String).new.accept(value: 1)
        CRYSTAL
      end

      expect_raises(Adamas::HIR::LoweringError, error_pattern) do
        lower_program_with_main(<<-CRYSTAL, source_backed: true)
          module SplatConcreteMappedExplicitAbi(T)
            def accept(value : T) : String
              value.to_s
            end
          end

          class SplatConcreteMappedExplicitAbiBox(T)
            include SplatConcreteMappedExplicitAbi(T)
          end

          SplatConcreteMappedExplicitAbiBox(String).new.accept(*{1})
        CRYSTAL
      end
    end

    it "rejects unproven call shapes for concrete generic receiver unions" do
      error_pattern = /unproven call shape for concrete generic receiver union/

      expect_raises(Adamas::HIR::LoweringError, error_pattern) do
        lower_program_with_main(<<-CRYSTAL)
          class NamedShapeBox(T)
            def initialize(@payload : T)
            end

            def fetch(tag : Int32 = 0) : T
              @payload
            end
          end

          def erased_fetch(value : NamedShapeBox(Int32) | NamedShapeBox(String))
            value.fetch(tag: 0)
          end

          erased_fetch(NamedShapeBox(Int32).new(1))
        CRYSTAL
      end

      previous_inline_yield = ENV["ADAMAS_DISABLE_INLINE_YIELD"]?
      ENV["ADAMAS_DISABLE_INLINE_YIELD"] = "1"
      begin
        expect_raises(Adamas::HIR::LoweringError, error_pattern) do
          lower_program_with_main(<<-CRYSTAL)
            class BlockShapeBox(T)
              def initialize(@payload : T)
              end

              def fetch(&) : T
                yield
                @payload
              end
            end

            def erased_fetch(value : BlockShapeBox(Int32) | BlockShapeBox(String))
              value.fetch { nil }
            end

            erased_fetch(BlockShapeBox(Int32).new(1))
          CRYSTAL
        end
      ensure
        if previous_inline_yield
          ENV["ADAMAS_DISABLE_INLINE_YIELD"] = previous_inline_yield
        else
          ENV.delete("ADAMAS_DISABLE_INLINE_YIELD")
        end
      end

      expect_raises(Adamas::HIR::LoweringError, error_pattern) do
        lower_program_with_main(<<-CRYSTAL)
          class SplatShapeBox(T)
            def initialize(@payload : T)
            end

            def fetch(tag : Int32) : T
              @payload
            end
          end

          def erased_fetch(value : SplatShapeBox(Int32) | SplatShapeBox(String))
            value.fetch(*{0})
          end

          erased_fetch(SplatShapeBox(Int32).new(1))
        CRYSTAL
      end
    end

    it "classifies value and reference owners from HIR descriptors" do
      converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
      module_ = converter.module
      module_.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Pointer,
        "Pointer(Int32)",
        [Adamas::HIR::TypeRef::INT32]
      ))
      # Insert the exact value descriptor before its reference-like base to
      # prove descriptor-only lookup prefers the full owner spelling.
      module_.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Struct,
        "ExactValue(Int32)",
        [Adamas::HIR::TypeRef::INT32]
      ))
      module_.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Class,
        "ExactValue"
      ))
      static_array_ref = module_.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Array,
        "StaticArray(Int32, 4)",
        [Adamas::HIR::TypeRef::INT32]
      ))
      array_ref = module_.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Array,
        "Array(Int32)",
        [Adamas::HIR::TypeRef::INT32]
      ))
      module_.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Tuple,
        "Tuple(Int32, String)",
        [Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::STRING]
      ))
      module_.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Primitive,
        "Int32"
      ))
      widget_ref = module_.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Class,
        "Widget"
      ))
      # Stale/mispaired layout flags must not turn reference descriptors into
      # value owners; descriptor spelling remains authoritative for these kinds.
      converter.__test_register_virtual_repair_class_info("StaticArray(Int32, 4)", static_array_ref, false)
      converter.__test_register_virtual_repair_class_info("Array(Int32)", array_ref, true)
      converter.__test_register_virtual_repair_class_info("Widget", widget_ref, true)
      generic_value_ref = module_.intern_type(Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Generic,
        "GenericBox(Int32)",
        [Adamas::HIR::TypeRef::INT32]
      ))
      converter.__test_register_virtual_repair_class_info("GenericBox(Int32)", generic_value_ref, true)

      mismatches = [] of String
      {
        {"Pointer(Int32)", true},
        {"ExactValue(Int32)", true},
        {"StaticArray(Int32, 4)", true},
        {"Tuple(Int32, String)", true},
        {"Int32", true},
        {"GenericBox(Int32)", true},
        {"Array(Int32)", false},
        {"Widget", false},
      }.each do |owner, expected_value|
        actual = converter.__test_concrete_value_virtual_repair_owner?(owner)
        mismatches << "#{owner}: expected=#{expected_value} actual=#{actual}" unless actual == expected_value
      end
      mismatches.should be_empty
    end

    it "does not synthesize an inherited generic wrapper during virtual-target replay" do
      source = <<-CRYSTAL
        class Parent
          def run(value : Int32) : Int32
            value
          end
        end

        class Box(T) < Parent
        end

        def invoke(io : Parent, value : Int32) : Int32
          io.run(value)
        end
      CRYSTAL

      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
      converter.arena = arena
      class_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode) }
      def_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode) }
      class_nodes.each { |node| converter.register_class(node) }
      def_nodes.each { |node| converter.register_function(node) }
      converter.__test_monomorphize_generic_class("Box", ["Int32"], "Box(Int32)")
      converter.lower_def(def_nodes.first)

      parent_target = converter.module.functions.find { |func| func.name.starts_with?("Parent#run$") }
      parent_target.should_not be_nil
      converter.module.has_function_with_body?(parent_target.not_nil!.name).should be_true

      # The generic child owner is a MIR runtime candidate, but its inherited
      # implementation is already available under the non-generic ancestor.
      converter.module.functions.any? { |func| func.name.starts_with?("Box(Int32)#run$") }.should be_false
    end

    it "does not queue an inherited child wrapper while its ancestor target is pending" do
      source = <<-CRYSTAL
        class Object
          def probe(value : Int32) : Int32
            value
          end
        end

        class Child < Object
        end
      CRYSTAL

      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
      converter.arena = arena
      class_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode) }
      def_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode) }
      class_nodes.each { |node| converter.register_class(node) }
      def_nodes.each { |node| converter.register_function(node) }
      converter.__test_set_lazy_rta_active(true)
      converter.__test_mark_live_type("Child")

      converter.__test_record_virtual_target_inside_lowering(
        "Object",
        "probe",
        [Adamas::HIR::TypeRef::INT32],
      )

      converter.__test_pending_function?("Object#probe$Int32").should be_true
      converter.__test_pending_function?("Child#probe$Int32").should be_false
      converter.__test_pending_function?("Child#probe").should be_false

      converter.__test_process_pending_lower_functions

      converter.module.has_function_with_body?("Object#probe$Int32").should be_true
      converter.module.functions.any? do |func|
        func.name.starts_with?("Child#probe") && converter.module.has_function_with_body?(func.name)
      end.should be_false
    ensure
      converter.try(&.__test_set_lazy_rta_active(false))
    end

    it "does not synthesize generic equality for an incompatible broad-root argument" do
      source = <<-CRYSTAL
        class Token
        end

        class Object
          abstract def ==(value : Token) : Bool
        end

        module EqualityFallback
          def ==(value : ::Token) : Bool
            false
          end
        end

        class Reference < Object
          include EqualityFallback
        end

        class Box(T) < Reference
          def ==(value : Box(T)) : Bool
            false
          end
        end

        def invoke_root(value : Object, token : Token) : Bool
          value == token
        end

        def invoke_box(value : Box(Int32), other : Box(Int32)) : Bool
          value == other
        end
      CRYSTAL

      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
      converter.arena = arena
      module_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::ModuleNode) }
      class_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode) }
      def_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode) }
      module_nodes.each { |node| converter.register_module(node) }
      class_nodes.each { |node| converter.register_class(node) }
      def_nodes.each { |node| converter.register_function(node) }
      converter.__test_monomorphize_generic_class("Box", ["Int32"], "Box(Int32)")
      converter.__test_mark_live_type("Box(Int32)")

      invoke_root = def_nodes.find { |node| String.new(node.name.not_nil!) == "invoke_root" }
      invoke_root.should_not be_nil
      converter.lower_def(invoke_root.not_nil!)

      converter.module.functions.any? do |func|
        func.name.starts_with?("Box(Int32)#==$Token") && converter.module.has_function_with_body?(func.name)
      end.should be_false
      converter.module.functions.any? do |func|
        func.name == "Box(Int32)#==$arity1" && converter.module.has_function_with_body?(func.name)
      end.should be_false

      executed = converter.__test_repair_missing_concrete_virtual_targets
      executed.should be >= 1
      inherited_target = converter.module.functions.find { |func| func.name.starts_with?("Reference#==$Token") }
      inherited_target.should_not be_nil
      converter.module.has_function_with_body?(inherited_target.not_nil!.name).should be_true
      converter.module.functions.any? do |func|
        func.name.starts_with?("Box(Int32)#==$Token") && converter.module.has_function_with_body?(func.name)
      end.should be_false
      converter.module.functions.any? do |func|
        func.name == "Box(Int32)#==$arity1" && converter.module.has_function_with_body?(func.name)
      end.should be_false

      invoke_box = def_nodes.find { |node| String.new(node.name.not_nil!) == "invoke_box" }
      invoke_box.should_not be_nil
      converter.lower_def(invoke_box.not_nil!)
      converter.module.functions.any? do |func|
        func.name.starts_with?("Box(Int32)#==$Box(Int32)") && converter.module.has_function_with_body?(func.name)
      end.should be_true
    end

    it "does not synthesize an inherited Reference wrapper when the ancestor body is reusable" do
      source = <<-CRYSTAL
        module Crystal
          struct Hasher
            def reference(value)
              self
            end
          end
        end

        class Reference
          def hash(hasher)
            hasher.reference(self)
          end
        end

        class Child < Reference
        end

        def invoke(value : Reference, hasher : Crystal::Hasher)
          value.hash(hasher)
        end
      CRYSTAL

      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
      converter.arena = arena
      class_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode) }
      def_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode) }
      class_nodes.each { |node| converter.register_class(node) }
      def_nodes.each { |node| converter.register_function(node) }
      converter.lower_def(def_nodes.first)
      converter.__test_mark_live_type("Child")
      converter.__test_replay_virtual_targets_for_registered_class("Child")

      parent_target = converter.module.functions.find { |func| func.name.starts_with?("Reference#hash$") }
      parent_target.should_not be_nil
      converter.module.has_function_with_body?(parent_target.not_nil!.name).should be_true
      parent_reference_call = parent_target.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end.find { |call| call.method_name.starts_with?("Crystal::Hasher#reference") }
      parent_reference_call.should_not be_nil
      parent_reference_call.not_nil!.method_name.should_not contain("$Child")

      # MIR resolves the concrete type id through the Reference ancestor. A
      # second body would only specialize the untyped helper on Child.
      converter.module.functions.any? { |func| func.name.starts_with?("Child#hash$") }.should be_false
      converter.module.functions.any? { |func| func.name.starts_with?("Crystal::Hasher#reference$Child") }.should be_false
    end

    it "materializes an inherited Reference body before deciding that a child wrapper is required" do
      source = <<-CRYSTAL
        module Crystal
          struct Hasher
            def reference(value)
              self
            end
          end
        end

        class Reference
          def hash(hasher : Crystal::Hasher)
            hasher.reference(self)
          end
        end

        class Child < Reference
        end
      CRYSTAL

      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
      converter.arena = arena
      class_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode) }
      class_nodes.each { |node| converter.register_class(node) }

      # Lazy RTA replays a newly recorded broad-root shape immediately for an
      # already-live child. Keep the inherited body absent at that rendezvous:
      # deciding reuse before materializing Reference#hash used to create a
      # parent-typed Child#hash wrapper.
      converter.__test_set_lazy_rta_active(true)
      converter.__test_mark_live_type("Child")
      converter.__test_record_virtual_target(
        "Reference",
        "hash",
        [converter.__test_type_ref_for_name("Crystal::Hasher")],
      )

      parent_target = converter.module.functions.find { |func| func.name.starts_with?("Reference#hash$") }
      parent_target.should_not be_nil
      converter.module.has_function_with_body?(parent_target.not_nil!.name).should be_true
      converter.module.functions.any? { |func| func.name.starts_with?("Child#hash$") }.should be_false
      converter.module.functions.any? { |func| func.name.starts_with?("Crystal::Hasher#reference$Child") }.should be_false
    ensure
      converter.try(&.__test_set_lazy_rta_active(false))
    end

    it "retains an exact runtime generic owner for an inherited Object wrapper" do
      source = <<-CRYSTAL
        class Object
          def inspect : String
            inspect(0)
            ""
          end

          def inspect(io : Int32) : Nil
          end

          def stable : Int32
            stable = 7
            stable
          end

          def indirect : Int32
            self.stable
          end

          def unrelated : Bool
            self == 1
          end
        end

        class Reference < Object
        end

        class Box(T) < Reference
          def inspect(io : Int32) : Nil
          end
        end
      CRYSTAL

      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
      converter.arena = arena
      class_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode) }
      class_nodes.each { |node| converter.register_class(node) }
      converter.__test_monomorphize_generic_class("Box", ["Int32"], "Box(Int32)")

      converter.__test_lower_function_if_needed("Box(Int32)#inspect")
      wrapper = converter.module.function_by_name("Box(Int32)#inspect")
      wrapper.should_not be_nil
      converter.__test_get_type_name_from_ref(wrapper.not_nil!.params.first.type).should eq("Box(Int32)")

      text = hir_text(wrapper.not_nil!)
      text.should contain("Box(Int32)#inspect$Int32")
      text.should_not contain("Object#inspect$Int32")

      converter.__test_lower_function_if_needed("Box(Int32)#stable")
      stable = converter.module.function_by_name("Box(Int32)#stable")
      stable.should_not be_nil
      converter.__test_get_type_name_from_ref(stable.not_nil!.params.first.type).should eq("Object")

      converter.__test_lower_function_if_needed("Box(Int32)#indirect")
      indirect = converter.module.function_by_name("Box(Int32)#indirect")
      indirect.should_not be_nil
      converter.__test_get_type_name_from_ref(indirect.not_nil!.params.first.type).should eq("Object")

      converter.__test_lower_function_if_needed("Box(Int32)#unrelated")
      unrelated = converter.module.function_by_name("Box(Int32)#unrelated")
      unrelated.should_not be_nil
      converter.__test_get_type_name_from_ref(unrelated.not_nil!.params.first.type).should eq("Object")
    end

    it "rejects noncanonical Object case-equality wrappers while the concrete target is pending" do
      wrappers = [
        "def ===(other, extra = 0) : Bool\n  self == other\nend",
        "def ===(other) : Bool\n  self == 1\nend",
        "def ===(other : String) : Bool\n  self == other\nend",
        "def ===(other) : Int32\n  self == other\nend",
      ]

      wrappers.each do |wrapper_source|
        source = <<-CRYSTAL
          class Object
            #{wrapper_source}

            def ==(other) : Bool
              false
            end
          end

          class Reference < Object
          end

          class Box(T) < Reference
            def ==(other : Int32) : Bool
              true
            end
          end

          def compare_noncanonical(box : Box(Int32), other : Int32) : Bool
            box === other
          end
        CRYSTAL

        arena, exprs = parse(source)
        converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
        converter.arena = arena
        class_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode) }
        def_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode) }
        class_nodes.each { |node| converter.register_class(node) }
        def_nodes.each { |node| converter.register_function(node) }
        converter.__test_monomorphize_generic_class("Box", ["Int32"], "Box(Int32)")

        converter.__test_queue_pending_inside_lowering("Box(Int32)#===$Int32")
        converter.lower_def(def_nodes.first)
        caller = converter.module.functions.find { |func| func.name.starts_with?("compare_noncanonical$") }
        caller.should_not be_nil
        case_equality_call = caller.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
          instruction.as?(Adamas::HIR::Call)
        end.find { |call| call.method_name.includes?("#===") }
        case_equality_call.should_not be_nil
        case_equality_call.not_nil!.method_name.should start_with("Object#===")
      end
    end

    it "retains an exact runtime generic owner when an Object wrapper redispatches through self" do
      source = <<-CRYSTAL
        class Object
          def ===(other) : Bool
            self == other
          end

          def ==(other) : Bool
            false
          end
        end

        class Reference < Object
          def ==(other : self) : Bool
            false
          end

          def ==(other) : Bool
            false
          end
        end

        class Box(T) < Reference
          def ==(other : Int32) : Bool
            true
          end
        end

        def compare(box : Box(Int32), other : Int32) : Bool
          box === other
        end

        def compare_unknown(box : Box(Int32), other) : Bool
          box === other
        end
      CRYSTAL

      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
      converter.arena = arena
      class_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode) }
      def_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode) }
      class_nodes.each { |node| converter.register_class(node) }
      def_nodes.each { |node| converter.register_function(node) }
      converter.__test_monomorphize_generic_class("Box", ["Int32"], "Box(Int32)")

      converter.__test_queue_pending_inside_lowering("Box(Int32)#===$Int32")
      converter.lower_def(def_nodes.first)
      caller = converter.module.functions.find { |func| func.name.starts_with?("compare$") }
      caller.should_not be_nil
      case_equality_call = caller.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end.find { |call| call.method_name.includes?("#===") }
      case_equality_call.should_not be_nil
      case_equality_call.not_nil!.method_name.should eq("Box(Int32)#===$Int32")
      converter.__test_pending_function?("Box(Int32)#===$Int32").should be_true
      converter.__test_pending_function?("Object#===$Int32").should be_false
      converter.module.has_function_with_body?("Object#===$Int32").should be_false

      converter.lower_def(def_nodes[1])
      unknown_caller = converter.module.functions.find { |func| func.name.starts_with?("compare_unknown$") }
      unknown_caller.should_not be_nil
      unknown_case_equality_call = unknown_caller.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end.find { |call| call.method_name.includes?("#===") }
      unknown_case_equality_call.should_not be_nil
      unknown_case_equality_call.not_nil!.method_name.should start_with("Object#===")

      converter.__test_process_pending_lower_functions
      converter.__test_lower_function_if_needed("Box(Int32)#===$Int32")
      wrapper = converter.module.function_by_name("Box(Int32)#===$Int32")
      wrapper.should_not be_nil
      converter.__test_get_type_name_from_ref(wrapper.not_nil!.params.first.type).should eq("Box(Int32)")
      wrapper.not_nil!.params.size.should eq(2)
      wrapper.not_nil!.params[1].type.should eq(Adamas::HIR::TypeRef::INT32)
      wrapper.not_nil!.return_type.should eq(Adamas::HIR::TypeRef::BOOL)

      equality_call = wrapper.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end.find { |call| call.method_name.includes?("#==") }
      equality_call.should_not be_nil
      equality_call.not_nil!.method_name.should eq("Box(Int32)#==$Int32")
      equality_call.not_nil!.type.should eq(Adamas::HIR::TypeRef::BOOL)
    end

    it "retains tracked enum owners for Object case-equality wrappers" do
      converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
        class Object
          def ===(other) : Bool
            self == other
          end

          def ==(other) : Bool
            false
          end
        end

        enum CaseKind
          First
          Second
        end

        enum OtherKind
          First
          Second
        end

        def exact_kind : CaseKind
          CaseKind::First
        end

        def nilable_kind : CaseKind?
          nil
        end

        def compare_exact : Bool
          case exact_kind
          when CaseKind::First
            true
          else
            false
          end
        end

        def compare_nilable : Bool
          case nilable_kind
          when CaseKind::First
            true
          else
            false
          end
        end

        def compare_nilable_receiver : Bool
          case CaseKind::First
          when nilable_kind
            true
          else
            false
          end
        end

        def compare_cross_owner : Bool
          case exact_kind
          when OtherKind::First
            true
          else
            false
          end
        end
      CRYSTAL

      nilable_receiver_caller = converter.module.functions.find do |func|
        func.name.starts_with?("compare_nilable_receiver")
      end
      nilable_receiver_caller.should_not be_nil
      nilable_receiver_call = nilable_receiver_caller.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end.find { |call| call.method_name.includes?("#===") }
      nilable_receiver_call.should_not be_nil
      nilable_receiver_call.not_nil!.method_name.should_not start_with("CaseKind#===")

      converter.__test_process_pending_lower_functions

      cross_owner_caller = converter.module.functions.find do |func|
        func.name.starts_with?("compare_cross_owner")
      end
      cross_owner_caller.should_not be_nil
      cross_owner_call = cross_owner_caller.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end.find { |call| call.method_name.includes?("#===") }
      cross_owner_call.should_not be_nil
      cross_owner_target = cross_owner_call.not_nil!.method_name
      cross_owner_target.should start_with("OtherKind#===")
      cross_owner_wrapper = converter.module.function_by_name(cross_owner_target)
      cross_owner_wrapper.should_not be_nil
      converter.module.has_function_with_body?(cross_owner_target).should be_true

      poisoned_caller = converter.module.functions.find { |func| func.name.starts_with?("compare_exact") }
      poisoned_caller.should_not be_nil
      poisoned_call = poisoned_caller.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end.find { |call| call.method_name.includes?("#===") }
      poisoned_call.should_not be_nil
      poisoned_caller.not_nil!.rewrite_call_method_name(
        poisoned_call.not_nil!,
        cross_owner_target,
      ).should be_true

      converter.__test_repair_receiver_bound_call_targets

      repaired_poisoned_call = poisoned_caller.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end.find { |call| call.method_name.includes?("#===") }
      repaired_poisoned_call.should_not be_nil
      repaired_poisoned_call.not_nil!.method_name.should eq("CaseKind#===$CaseKind")
      converter.module.has_function_with_body?("CaseKind#===$Nil | CaseKind").should be_true
      poisoned_caller.not_nil!.rewrite_call_method_name(
        repaired_poisoned_call.not_nil!,
        "CaseKind#===$Nil | CaseKind",
      ).should be_true

      converter.__test_repair_receiver_bound_call_targets

      {
        "compare_exact"   => "CaseKind#===$CaseKind",
        "compare_nilable" => "CaseKind#===$Nil | CaseKind",
      }.each do |caller_prefix, expected_target|
        caller = converter.module.functions.find { |func| func.name.starts_with?(caller_prefix) }
        caller.should_not be_nil

        case_equality_call = caller.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
          instruction.as?(Adamas::HIR::Call)
        end.find { |call| call.method_name.includes?("#===") }
        case_equality_call.should_not be_nil
        case_equality_call.not_nil!.method_name.should eq(expected_target)
        case_equality_call.not_nil!.type.should eq(Adamas::HIR::TypeRef::BOOL)
        case_equality_call.not_nil!.virtual.should be_false
        case_equality_call.not_nil!.block.should be_nil

        wrapper = converter.module.function_by_name(expected_target)
        wrapper.should_not be_nil
        converter.module.has_function_with_body?(expected_target).should be_true
        wrapper.not_nil!.return_type.should eq(Adamas::HIR::TypeRef::BOOL)
        wrapper.not_nil!.params.size.should eq(2)
        receiver_type = caller.not_nil!.blocks.flat_map(&.instructions).find do |instruction|
          instruction.id == case_equality_call.not_nil!.receiver_value
        end.try(&.type)
        receiver_type.should_not be_nil
        receiver_type.not_nil!.should eq(Adamas::HIR::TypeRef::INT32)
        wrapper.not_nil!.params.first.type.should eq(receiver_type.not_nil!)
        argument_type = caller.not_nil!.blocks.flat_map(&.instructions).find do |instruction|
          instruction.id == case_equality_call.not_nil!.args.first
        end.try(&.type)
        argument_type.should_not be_nil
        wrapper.not_nil!.params[1].type.should eq(argument_type.not_nil!)
      end
    end

    it "does not synthesize a generic wrapper for an Object virtual target" do
      source = <<-CRYSTAL
        class Object
          def to_s : String
            "object"
          end
        end

        class Box(T) < Object
        end

        def invoke(io : Object) : String
          io.to_s
        end
      CRYSTAL

      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
      converter.arena = arena
      class_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode) }
      def_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode) }
      class_nodes.each { |node| converter.register_class(node) }
      def_nodes.each { |node| converter.register_function(node) }
      converter.__test_monomorphize_generic_class("Box", ["Int32"], "Box(Int32)")
      converter.lower_def(def_nodes.first)
      converter.__test_mark_live_type("Box(Int32)")

      object_target = converter.module.functions.find { |func| func.name.starts_with?("Object#to_s") }
      object_target.should_not be_nil
      converter.module.has_function_with_body?(object_target.not_nil!.name).should be_true
      converter.module.functions.any? { |func| func.name.starts_with?("Box(Int32)#to_s") }.should be_false
    end

    it "does not materialize an unsuffixed sibling for an annotated broad target" do
      source = <<-CRYSTAL
        class Object
          def render : Int32
            11
          end

          def render(sink : Sink) : Int32
            22
          end
        end

        class Reference < Object
        end

        class Sink < Reference
        end

        class FancySink < Sink
        end

        class Box(T) < Reference
        end
      CRYSTAL

      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
      converter.arena = arena
      class_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode) }
      def_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode) }
      class_nodes.each { |node| converter.register_class(node) }
      def_nodes.each { |node| converter.register_function(node) }
      converter.__test_monomorphize_generic_class("Box", ["Int32"], "Box(Int32)")
      converter.__test_set_lazy_rta_active(true)
      converter.__test_mark_live_type("Box(Int32)")

      converter.__test_record_virtual_target(
        "Object",
        "render",
        [converter.__test_type_ref_for_name("FancySink")],
      )

      converter.module.has_function_with_body?("Object#render$Sink").should be_true
      converter.module.has_function_with_body?("Object#render").should be_false
      converter.module.functions.any? do |func|
        func.name.starts_with?("Box(Int32)#render") && converter.module.has_function_with_body?(func.name)
      end.should be_false
    ensure
      converter.try(&.__test_set_lazy_rta_active(false))
    end

    it "defers broad-root override fanout until the concrete child is live" do
      source = <<-CRYSTAL
        class Object
          def probe(value : Int32) : Int32
            value
          end
        end

        class Box(T) < Object
          def probe(value : Int32) : Int32
            value + 1
          end
        end

        def invoke(value : Object) : Int32
          value.probe(1)
        end
      CRYSTAL

      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
      converter.arena = arena
      class_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode) }
      def_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode) }
      class_nodes.each { |node| converter.register_class(node) }
      def_nodes.each { |node| converter.register_function(node) }
      converter.__test_monomorphize_generic_class("Box", ["Int32"], "Box(Int32)")
      converter.__test_monomorphize_generic_class("Box", ["String"], "Box(String)")
      converter.__test_mark_live_type("Box(String)")

      invoke_node = def_nodes.find { |node| String.new(node.name.not_nil!) == "invoke" }
      invoke_node.should_not be_nil
      converter.lower_def(invoke_node.not_nil!)

      object_target = converter.module.functions.find { |func| func.name.starts_with?("Object#probe$") }
      object_target.should_not be_nil
      converter.module.has_function_with_body?(object_target.not_nil!.name).should be_true
      converter.module.functions.any? { |func| func.name.starts_with?("Box(Int32)#probe$") }.should be_false
      live_target = converter.module.functions.find { |func| func.name.starts_with?("Box(String)#probe$") }
      live_target.should_not be_nil
      converter.module.has_function_with_body?(live_target.not_nil!.name).should be_true

      converter.__test_set_lazy_rta_active(true)
      converter.__test_mark_live_type("Box(Int32)")

      child_target = converter.module.functions.find { |func| func.name.starts_with?("Box(Int32)#probe$") }
      child_target.should_not be_nil
      converter.module.has_function_with_body?(child_target.not_nil!.name).should be_true
    ensure
      converter.try(&.__test_set_lazy_rta_active(false))
    end

    it "defers bare generic virtual targets until each concrete instance is live" do
      source = <<-CRYSTAL
        class Object
        end

        class Box(T) < Object
          def probe(value : Int32) : Int32
            value + 1
          end
        end
      CRYSTAL

      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
      converter.arena = arena
      class_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode) }
      class_nodes.each { |node| converter.register_class(node) }
      converter.__test_monomorphize_generic_class("Box", ["Int32"], "Box(Int32)")
      converter.__test_monomorphize_generic_class("Box", ["String"], "Box(String)")
      converter.__test_set_lazy_rta_active(true)
      converter.__test_mark_live_type("Box(String)")

      converter.__test_record_virtual_target("Box", "probe", [Adamas::HIR::TypeRef::INT32])

      live_target = converter.module.functions.find { |func| func.name.starts_with?("Box(String)#probe$") }
      live_target.should_not be_nil
      converter.module.has_function_with_body?(live_target.not_nil!.name).should be_true
      converter.module.functions.any? do |func|
        func.name.starts_with?("Box(Int32)#probe$") && converter.module.has_function_with_body?(func.name)
      end.should be_false

      converter.__test_monomorphize_generic_class("Box", ["Float64"], "Box(Float64)")
      converter.module.functions.any? do |func|
        func.name.starts_with?("Box(Float64)#probe$") && converter.module.has_function_with_body?(func.name)
      end.should be_false

      converter.__test_mark_live_type("Box(Int32)")

      late_target = converter.module.functions.find { |func| func.name.starts_with?("Box(Int32)#probe$") }
      late_target.should_not be_nil
      converter.module.has_function_with_body?(late_target.not_nil!.name).should be_true

      converter.__test_mark_live_type("Box(Float64)")
      registered_late_target = converter.module.functions.find { |func| func.name.starts_with?("Box(Float64)#probe$") }
      registered_late_target.should_not be_nil
      converter.module.has_function_with_body?(registered_late_target.not_nil!.name).should be_true
    ensure
      converter.try(&.__test_set_lazy_rta_active(false))
    end

    it "does not make an instance type live from a class-method call" do
      source = <<-CRYSTAL
        class Object
          def probe : Int32
            1
          end
        end

        class Box(T) < Object
          def self.touch : Int32
            2
          end

          def probe : Int32
            3
          end
        end
      CRYSTAL

      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
      converter.arena = arena
      class_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode) }
      def_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode) }
      class_nodes.each { |node| converter.register_class(node) }
      def_nodes.each { |node| converter.register_function(node) }
      converter.__test_monomorphize_generic_class("Box", ["Int32"], "Box(Int32)")
      converter.__test_set_lazy_rta_active(true)
      converter.__test_record_virtual_target("Object", "probe", [] of Adamas::HIR::TypeRef)

      caller = converter.module.create_function("class_method_only", Adamas::HIR::TypeRef::INT32)
      caller.get_block(caller.entry_block).add(
        Adamas::HIR::Call.without_receiver(
          caller.next_value_id,
          Adamas::HIR::TypeRef::INT32,
          "Box(Int32).touch",
          [] of Adamas::HIR::ValueId,
        )
      )
      converter.__test_scan_hir_function_for_live_types(caller)

      converter.module.functions.any? do |func|
        func.name.starts_with?("Box(Int32)#probe") && converter.module.has_function_with_body?(func.name)
      end.should be_false

      caller.get_block(caller.entry_block).add(
        Adamas::HIR::Call.without_receiver(
          caller.next_value_id,
          Adamas::HIR::TypeRef::VOID,
          "Box(Int32).new",
          [] of Adamas::HIR::ValueId,
        )
      )
      converter.__test_scan_hir_function_for_live_types(caller)

      converter.module.functions.any? do |func|
        func.name.starts_with?("Box(Int32)#probe") && converter.module.has_function_with_body?(func.name)
      end.should be_true
    ensure
      converter.try(&.__test_set_lazy_rta_active(false))
    end

    it "does not treat late generic registration as broad-root liveness" do
      source = <<-CRYSTAL
        class Object
          def probe(value : Int32) : Int32
            value
          end
        end

        class Box(T) < Object
          def probe(value : Int32) : Int32
            value + 1
          end
        end

        def invoke(value : Object) : Int32
          value.probe(1)
        end
      CRYSTAL

      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
      converter.arena = arena
      class_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode) }
      def_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode) }
      class_nodes.each { |node| converter.register_class(node) }
      def_nodes.each { |node| converter.register_function(node) }

      converter.__test_monomorphize_generic_class("Box", ["String"], "Box(String)")
      converter.__test_mark_live_type("Box(String)")

      invoke_node = def_nodes.find { |node| String.new(node.name.not_nil!) == "invoke" }
      invoke_node.should_not be_nil
      converter.lower_def(invoke_node.not_nil!)
      converter.module.functions.any? { |func| func.name.starts_with?("Box(String)#probe$") }.should be_true

      converter.__test_monomorphize_generic_class("Box", ["Int32"], "Box(Int32)")
      converter.module.functions.any? { |func| func.name.starts_with?("Box(Int32)#probe$") }.should be_false

      converter.__test_set_lazy_rta_active(true)
      converter.__test_mark_live_type("Box(Int32)")

      target = converter.module.functions.find { |func| func.name.starts_with?("Box(Int32)#probe$") }
      target.should_not be_nil
      converter.module.has_function_with_body?(target.not_nil!.name).should be_true
    ensure
      converter.try(&.__test_set_lazy_rta_active(false))
    end

    it "replays broad targets for late generic registration when lazy RTA is disabled" do
      previous_lazy_rta = ENV["ADAMAS_LAZY_RTA"]?
      ENV["ADAMAS_LAZY_RTA"] = "0"
      source = <<-CRYSTAL
        class Object
          def probe(value : Int32) : Int32
            value
          end
        end

        class Box(T) < Object
          def probe(value : Int32) : Int32
            value + 1
          end
        end

        def invoke(value : Object) : Int32
          value.probe(1)
        end
      CRYSTAL

      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
      converter.arena = arena
      class_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode) }
      def_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode) }
      class_nodes.each { |node| converter.register_class(node) }
      def_nodes.each { |node| converter.register_function(node) }

      converter.__test_monomorphize_generic_class("Box", ["String"], "Box(String)")
      invoke_node = def_nodes.find { |node| String.new(node.name.not_nil!) == "invoke" }
      invoke_node.should_not be_nil
      converter.lower_def(invoke_node.not_nil!)

      converter.__test_monomorphize_generic_class("Box", ["Int32"], "Box(Int32)")
      target = converter.module.functions.find { |func| func.name.starts_with?("Box(Int32)#probe$") }
      target.should_not be_nil
      converter.module.has_function_with_body?(target.not_nil!.name).should be_true
    ensure
      if previous_lazy_rta
        ENV["ADAMAS_LAZY_RTA"] = previous_lazy_rta
      else
        ENV.delete("ADAMAS_LAZY_RTA")
      end
    end

    it "replays a broad target when an already-live child enters lazy RTA" do
      source = <<-CRYSTAL
        class Object
          def probe(value : Int32) : Int32
            value
          end
        end

        class Child < Object
          def probe(value : Int32) : Int32
            value + 1
          end
        end

      CRYSTAL

      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
      converter.arena = arena
      class_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode) }
      class_nodes.each { |node| converter.register_class(node) }

      # Broad roots defer replay outside lazy RTA. The later observation of an
      # already-live child is therefore a required rendezvous with that target.
      converter.__test_mark_live_type("Child")
      converter.__test_record_virtual_target("Object", "probe", [Adamas::HIR::TypeRef::INT32])
      converter.module.functions.any? do |func|
        func.name.starts_with?("Child#probe$") && converter.module.has_function_with_body?(func.name)
      end.should be_false

      converter.__test_set_lazy_rta_active(true)
      converter.__test_mark_live_type("Child")

      target = converter.module.functions.find { |func| func.name.starts_with?("Child#probe$") }
      target.should_not be_nil
      converter.module.has_function_with_body?(target.not_nil!.name).should be_true
    ensure
      converter.try(&.__test_set_lazy_rta_active(false))
    end

    it "does not repair a concrete value owner admitted under an Object virtual demand" do
      # Synthetic hierarchy fixture: Crystal structs cannot spell an explicit
      # superclass, so these declarations model the built-in Object/Value/Struct
      # chain needed to exercise replay admission for a concrete value owner.
      source = <<-CRYSTAL
        class Object
          def probe : Int32
            0
          end
        end

        class Value < Object
        end

        class Struct < Value
        end

        struct Box
          def probe : Int32
            7
          end
        end

        def invoke(value : Object) : Int32
          value.probe
        end

        def static_probe(value : Box) : Int32
          value.probe
        end
      CRYSTAL

      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
      converter.arena = arena
      class_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode) }
      def_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode) }
      class_nodes.each { |node| converter.register_class(node) }
      def_nodes.each { |node| converter.register_function(node) }

      # Prove the concrete value method is registered and remains a static call
      # before exercising the Object-root virtual demand.
      converter.__test_function_def_names("Box#probe").should_not be_empty
      converter.__test_collect_subclasses_cached("Object").should contain("Box")
      static_node = def_nodes.find { |node| String.new(node.name.not_nil!) == "static_probe" }
      static_node.should_not be_nil
      converter.lower_def(static_node.not_nil!)
      static = converter.module.functions.find { |func| func.name.starts_with?("static_probe$") }
      static.should_not be_nil
      static_calls = static.not_nil!.blocks.flat_map(&.instructions).compact_map { |inst| inst.as?(Adamas::HIR::Call) }
      static_calls.any? { |call| call.method_name.starts_with?("Box#probe") }.should be_true
      static_calls.none?(&.virtual).should be_true

      invoke_node = def_nodes.find { |node| String.new(node.name.not_nil!) == "invoke" }
      invoke_node.should_not be_nil
      converter.lower_def(invoke_node.not_nil!)
      invoke = converter.module.functions.find { |func| func.name.starts_with?("invoke$") }
      invoke.should_not be_nil
      invoke.not_nil!.blocks.flat_map(&.instructions).any? do |inst|
        inst.is_a?(Adamas::HIR::Call) && inst.virtual
      end.should be_true
      converter.__test_mark_live_type("Box")
      converter.__test_replay_virtual_targets_for_registered_class("Box")

      target_names = converter.module.functions
        .select { |func| func.name.starts_with?("Box#probe") }
        .map(&.name)
      target_names.should_not be_empty
      target_names.each do |target_name|
        converter.module.has_function_with_body?(target_name).should be_true
        converter.module.remove_function(target_name).should be_true
        converter.__test_reset_lowering_state(target_name)
      end
      converter.__test_mark_live_type("Box")
      target_names.each do |target_name|
        converter.module.has_function_with_body?(target_name).should be_false
        converter.module.functions.any? { |func| func.name == target_name }.should be_false
      end

      executed = converter.__test_repair_missing_concrete_virtual_targets

      # A value owner can satisfy the Object-root demand statically, but final
      # repair must not fan out and recreate its removed body.
      target_names.each do |target_name|
        converter.module.has_function_with_body?(target_name).should be_false
        converter.module.functions.any? { |func| func.name == target_name }.should be_false
      end
      executed.should eq(0)
    end

    it "recovers a removed target from the recorded virtual demand" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class Parent
          def run(value : Int32) : Int32
            value
          end
        end

        class Child < Parent
          def run(value : Int32) : Int32
            value + 1
          end
        end

        def invoke(io : Parent, value : Int32) : Int32
          io.run(value)
        end

        invoke(Child.new, 1)
      CRYSTAL

      caller = converter.module.functions.find { |func| func.name.starts_with?("invoke$") }
      caller.should_not be_nil
      caller.not_nil!.blocks.flat_map(&.instructions).any? do |inst|
        inst.is_a?(Adamas::HIR::Call) && inst.virtual
      end.should be_true

      target = converter.module.functions.find { |func| func.name.starts_with?("Child#run$") }
      target.should_not be_nil
      target_name = target.not_nil!.name

      converter.module.remove_function(caller.not_nil!.name).should be_true
      converter.module.remove_function(target_name).should be_true
      converter.__test_reset_lowering_state(target_name)
      converter.__test_mark_live_type("Child")
      converter.module.has_function_with_body?(target_name).should be_false

      converter.__test_repair_missing_concrete_virtual_targets

      # The only recorded demand came from `caller`; once that body is gone,
      # the registry entry is historical evidence and must not reactivate the
      # removed concrete owner.
      converter.module.has_function_with_body?(target_name).should be_false
    end

    it "repairs when a second caller with the same demand survives" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class Parent
          def run(value : Int32) : Int32
            value
          end
        end

        class Child < Parent
          def run(value : Int32) : Int32
            value + 1
          end
        end

        def invoke_a(io : Parent, value : Int32) : Int32
          io.run(value)
        end

        def invoke_b(io : Parent, value : Int32) : Int32
          io.run(value)
        end

        invoke_a(Child.new, 1)
        invoke_b(Child.new, 2)
      CRYSTAL

      caller_a = converter.module.functions.find { |func| func.name.starts_with?("invoke_a$") }
      caller_b = converter.module.functions.find { |func| func.name.starts_with?("invoke_b$") }
      caller_a.should_not be_nil
      caller_b.should_not be_nil

      target = converter.module.functions.find { |func| func.name.starts_with?("Child#run$") }
      target.should_not be_nil
      target_name = target.not_nil!.name

      converter.module.remove_function(caller_a.not_nil!.name).should be_true
      converter.module.remove_function(target_name).should be_true
      converter.__test_reset_lowering_state(target_name)
      converter.__test_mark_live_type("Child")
      converter.module.has_function_with_body?(target_name).should be_false

      converter.__test_repair_missing_concrete_virtual_targets

      converter.module.has_function_with_body?(target_name).should be_true
    end

    it "does not recreate an inherited child wrapper when the parent body remains" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class Parent
          def run(value : Int32) : Int32
            value
          end
        end

        class Child < Parent
        end

        def invoke(io : Parent, value : Int32) : Int32
          io.run(value)
        end

        invoke(Child.new, 1)
      CRYSTAL

      caller = converter.module.functions.find { |func| func.name.starts_with?("invoke$") }
      caller.should_not be_nil
      caller.not_nil!.blocks.flat_map(&.instructions).any? do |inst|
        inst.is_a?(Adamas::HIR::Call) && inst.virtual
      end.should be_true

      parent_target = converter.module.functions.find { |func| func.name.starts_with?("Parent#run$") }
      # Materialize the redundant wrapper explicitly: initial replay now uses
      # the same ancestor-body proof as final repair and omits it by default.
      converter.__test_lower_function_if_needed("Child#run$Int32")
      child_target = converter.module.functions.find { |func| func.name.starts_with?("Child#run$") }
      parent_target.should_not be_nil
      child_target.should_not be_nil
      parent_name = parent_target.not_nil!.name
      child_name = child_target.not_nil!.name
      converter.module.has_function_with_body?(parent_name).should be_true

      converter.module.remove_function(child_name).should be_true
      converter.__test_reset_lowering_state(child_name)
      converter.__test_mark_live_type("Child")
      converter.module.has_function_with_body?(child_name).should be_false

      converter.__test_repair_missing_concrete_virtual_targets

      converter.module.has_function_with_body?(parent_name).should be_true
      # MIR resolves Child#run through Parent#run; a missing synthetic child
      # wrapper is therefore not a repair request when the ancestor body lives.
      converter.module.has_function_with_body?(child_name).should be_false
    end

    it "does not recreate an inherited generic child wrapper when the parent body remains" do
      source = <<-CRYSTAL
        class Parent
          def run(value : Int32) : Int32
            value
          end
        end

        class Box(T) < Parent
        end

        def invoke(io : Parent, value : Int32) : Int32
          io.run(value)
        end
      CRYSTAL

      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
      converter.arena = arena
      class_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode) }
      def_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode) }
      class_nodes.each { |node| converter.register_class(node) }
      def_nodes.each { |node| converter.register_function(node) }
      converter.__test_monomorphize_generic_class("Box", ["Int32"], "Box(Int32)")
      converter.lower_def(def_nodes.first)

      caller = converter.module.functions.find { |func| func.name.starts_with?("invoke$") }
      caller.should_not be_nil
      caller.not_nil!.blocks.flat_map(&.instructions).any? do |inst|
        inst.is_a?(Adamas::HIR::Call) && inst.virtual
      end.should be_true

      parent_target = converter.module.functions.find { |func| func.name.starts_with?("Parent#run$") }
      # The replay path intentionally omits this redundant wrapper. Materialize
      # it explicitly so this test can exercise final-repair behavior after a
      # previously emitted target is removed.
      converter.__test_lower_function_if_needed("Box(Int32)#run$Int32")
      child_target = converter.module.functions.find { |func| func.name.starts_with?("Box(Int32)#run$") }
      parent_target.should_not be_nil
      child_target.should_not be_nil
      parent_name = parent_target.not_nil!.name
      child_name = child_target.not_nil!.name
      converter.module.has_function_with_body?(parent_name).should be_true

      converter.module.remove_function(child_name).should be_true
      converter.__test_reset_lowering_state(child_name)
      converter.__test_mark_live_type("Box(Int32)")
      converter.module.has_function_with_body?(child_name).should be_false

      converter.__test_repair_missing_concrete_virtual_targets

      converter.module.has_function_with_body?(parent_name).should be_true
      # MIR can map the concrete Box runtime type id to Parent#run. A missing
      # generic child wrapper is therefore not a repair request when the
      # ancestor body is already available.
      converter.module.has_function_with_body?(child_name).should be_false
    end

    it "restores an ancestor implementation when the inherited body is missing" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class Parent
          def run(value : Int32) : Int32
            value
          end
        end

        class Child < Parent
        end

        def invoke(io : Parent, value : Int32) : Int32
          io.run(value)
        end

        invoke(Child.new, 1)
      CRYSTAL

      parent_target = converter.module.functions.find { |func| func.name.starts_with?("Parent#run$") }
      # This test removes both implementations to exercise restoration, so
      # create the otherwise redundant child wrapper as explicit setup.
      converter.__test_lower_function_if_needed("Child#run$Int32")
      child_target = converter.module.functions.find { |func| func.name.starts_with?("Child#run$") }
      parent_target.should_not be_nil
      child_target.should_not be_nil
      parent_name = parent_target.not_nil!.name
      child_name = child_target.not_nil!.name

      converter.module.remove_function(parent_name).should be_true
      converter.module.remove_function(child_name).should be_true
      converter.__test_reset_lowering_state(parent_name)
      converter.__test_reset_lowering_state(child_name)
      converter.__test_mark_live_type("Child")
      converter.module.has_function_with_body?(parent_name).should be_false

      converter.__test_repair_missing_concrete_virtual_targets

      converter.module.has_function_with_body?(parent_name).should be_true
      # The inherited request must reuse the restored ancestor source rather
      # than materialize a redundant concrete child wrapper.
      converter.module.has_function_with_body?(child_name).should be_false
    end

    it "revalidates stale inherited repairs after restoring the parent body" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class Parent
          def run(value : Int32) : Int32
            value
          end
        end

        class ChildA < Parent
        end

        class ChildB < Parent
        end

        def invoke(io : Parent, value : Int32) : Int32
          io.run(value)
        end

        invoke(ChildA.new, 1)
        invoke(ChildB.new, 2)
      CRYSTAL

      caller = converter.module.functions.find { |func| func.name.starts_with?("invoke$") }
      caller.should_not be_nil
      caller.not_nil!.blocks.flat_map(&.instructions).any? do |inst|
        inst.is_a?(Adamas::HIR::Call) && inst.virtual
      end.should be_true

      parent_target = converter.module.functions.find { |func| func.name.starts_with?("Parent#run$") }
      # Initial replay omits inherited wrappers whose ancestor body is already
      # sufficient. Create them explicitly before simulating stale removals.
      converter.__test_lower_function_if_needed("ChildA#run$Int32")
      converter.__test_lower_function_if_needed("ChildB#run$Int32")
      child_a_target = converter.module.functions.find { |func| func.name.starts_with?("ChildA#run$") }
      child_b_target = converter.module.functions.find { |func| func.name.starts_with?("ChildB#run$") }
      parent_target.should_not be_nil
      child_a_target.should_not be_nil
      child_b_target.should_not be_nil
      parent_name = parent_target.not_nil!.name
      child_a_name = child_a_target.not_nil!.name
      child_b_name = child_b_target.not_nil!.name

      converter.module.remove_function(parent_name).should be_true
      converter.module.remove_function(child_a_name).should be_true
      converter.module.remove_function(child_b_name).should be_true
      converter.__test_reset_lowering_state(parent_name)
      converter.__test_reset_lowering_state(child_a_name)
      converter.__test_reset_lowering_state(child_b_name)
      converter.__test_mark_live_type("ChildA")
      converter.__test_mark_live_type("ChildB")
      converter.module.has_function_with_body?(parent_name).should be_false

      executed = converter.__test_repair_missing_concrete_virtual_targets

      converter.module.has_function_with_body?(parent_name).should be_true
      converter.module.has_function_with_body?(child_a_name).should be_false
      converter.module.has_function_with_body?(child_b_name).should be_false
      executed.should eq(1)
    end

    it "restores a concrete generic owner when the body depends on its type parameter" do
      source = <<-CRYSTAL
        module Runner(T)
          def run(value : T) : T
            value
          end
        end

        class Parent
          include Runner(Int32)
        end

        class Box(T) < Parent
        end

        def invoke(io : Parent, value : Int32) : Int32
          io.run(value)
        end
      CRYSTAL

      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
      converter.arena = arena
      module_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::ModuleNode) }
      class_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode) }
      def_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode) }
      module_nodes.each { |node| converter.register_module(node) }
      class_nodes.each { |node| converter.register_class(node) }
      def_nodes.each { |node| converter.register_function(node) }
      converter.__test_monomorphize_generic_class("Box", ["Int32"], "Box(Int32)")
      converter.lower_def(def_nodes.first)

      child_target = converter.module.functions.find { |func| func.name.starts_with?("Box(Int32)#run$") }
      child_target.should_not be_nil
      child_name = child_target.not_nil!.name
      converter.__test_get_type_name_from_ref(child_target.not_nil!.return_type).should eq("Int32")

      converter.module.remove_function(child_name).should be_true
      converter.__test_reset_lowering_state(child_name)
      converter.__test_mark_live_type("Box(Int32)")
      converter.module.has_function_with_body?(child_name).should be_false

      functions_before_repair = converter.module.functions.map(&.name).to_set
      converter.__test_repair_missing_concrete_virtual_targets

      converter.module.has_function_with_body?(child_name).should be_true
      functions_after_repair = converter.module.functions.map(&.name).to_set
      (functions_after_repair - functions_before_repair).should eq(Set{child_name})
    end
  end

  describe "virtual target hierarchy cache" do
    it "replays a child registered after the parent cache was warmed" do
      source = <<-CRYSTAL
        class Parent
          def run(value : Int32) : Int32
            value
          end
        end

        class Seed < Parent
        end

        class Child < Parent
          def run(value : Int32) : Int32
            value + 1
          end
        end

        def invoke(io : Parent, value : Int32) : Int32
          io.run(value)
        end
      CRYSTAL
      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
      converter.arena = arena

      class_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode) }
      invoke_node = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode) }.first
      parent_node = class_nodes.find { |node| String.new(node.name) == "Parent" }
      child_node = class_nodes.find { |node| String.new(node.name) == "Child" }
      parent_node.should_not be_nil
      child_node.should_not be_nil
      invoke_node.should_not be_nil

      converter.register_class(parent_node.not_nil!)
      seed_node = class_nodes.find { |node| String.new(node.name) == "Seed" }
      seed_node.should_not be_nil
      converter.register_class(seed_node.not_nil!)
      converter.register_function(invoke_node.not_nil!)
      converter.lower_def(invoke_node.not_nil!)
      converter.__test_collect_subclasses_cached("Parent").should contain("Seed")

      converter.register_class(child_node.not_nil!)
      converter.__test_collect_subclasses_cached("Parent").should contain("Child")

      target = converter.module.functions.find { |func| func.name.starts_with?("Child#run$") }
      target.should_not be_nil
      target_name = target.not_nil!.name
      converter.module.remove_function(target_name).should be_true
      converter.__test_reset_lowering_state(target_name)
      converter.__test_mark_live_type("Child")

      converter.__test_repair_missing_concrete_virtual_targets
      converter.module.has_function_with_body?(target_name).should be_true
    end
  end

  describe "default arg lexical context" do
    it "resolves nested constants in class method defaults against the callee owner" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class Outer
          def self.wrap(value : ExecutionContext = ExecutionContext.current)
            value
          end
        end

        class Outer::ExecutionContext
          def self.current : Outer::ExecutionContext
            new
          end
        end

        Outer.wrap()
      CRYSTAL

      main = converter.module.function_by_name("__adamas_main")
      main.should_not be_nil

      text = hir_text(main.not_nil!)
      text.should contain("call Outer::ExecutionContext.current()")
      text.should contain("call Outer.wrap$Outer::ExecutionContext")
      text.should_not contain("NotFoundError#current")
    end
  end

  describe "implicit zero-arg member receivers" do
    it "resolves bare methods from transitive generic module inclusions" do
      converter = lower_program_with_main(<<-CRYSTAL)
        module EnumerableLike(T)
          def to_set : Int32
            7
          end
        end

        module IndexableLike(T)
          include EnumerableLike(T)
        end

        class Bag(T)
          include IndexableLike(T)

          def uniq
            to_set
          end
        end

        Bag(UInt32).new.uniq
      CRYSTAL

      converter.__test_lower_function_if_needed("Bag(UInt32)#uniq")

      func = converter.module.function_by_name("Bag(UInt32)#uniq")
      func.should_not be_nil
      text = hir_text(func.not_nil!)
      text.should contain("call %")
      text.should contain("Bag(UInt32)#to_set")
      text.should_not contain("local \"to_set\" : 0")
      text.should_not contain("local \"to_set\" : Void")
    end

    it "materializes a typed method from a transitive generic module inclusion" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class HashState
        end

        class Object
          abstract def hash(state : HashState) : HashState
        end

        module HashLike(T)
          def hash(state : HashState) : HashState
            state
          end
        end

        module MutableHashLike(T)
          include HashLike(T)
        end

        struct FixedHashLike(T, N)
          include MutableHashLike(T)
        end

        def hash_fixed(value : FixedHashLike(UInt8, Int32), state : HashState)
          value.hash(state)
        end

        hash_fixed(FixedHashLike(UInt8, Int32).new, HashState.new)
      CRYSTAL

      target_name = "FixedHashLike(UInt8, Int32)#hash$HashState"
      converter.__test_lower_function_if_needed(target_name)

      target = converter.module.function_by_name(target_name)
      target.should_not be_nil
      target.not_nil!.blocks.any? { |block| !block.instructions.empty? }.should be_true

      converter.module.remove_function(target_name).should be_true
      converter.__test_reset_lowering_state(target_name)
      converter.__test_lower_receiver_repair_targets_with_fallbacks([
        {
          target_name,
          "FixedHashLike(UInt8, Int32)#hash",
          [converter.__test_type_ref_for_name("HashState")],
        },
      ])

      converter.module.has_function_with_body?(target_name).should be_true
    end

    it "prefers a lazy included-module body over an inherited parent body" do
      source = <<-CRYSTAL
        class LazyHashState
        end

        module LazyHashLike(T)
          def hash(state : LazyHashState) : Int32
            7
          end
        end

        module LazyMutableHashLike(T)
          include LazyHashLike(T)
        end

        class LazyHashParent
          def hash(state : LazyHashState) : Int32
            9
          end
        end

        class LazyFixedHash(T) < LazyHashParent
          include LazyMutableHashLike(T)
        end
      CRYSTAL
      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena
      converter.__test_set_lazy_module_methods(true)

      exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ModuleNode)
      end.each { |node| converter.register_module(node) }
      exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
      end.each { |node| converter.register_class(node) }
      converter.__test_monomorphize_generic_class(
        "LazyFixedHash",
        ["UInt8"],
        "LazyFixedHash(UInt8)",
      )

      target_name = "LazyFixedHash(UInt8)#hash$LazyHashState"
      converter.__test_remember_callsite_arg_types(
        target_name,
        [converter.__test_type_ref_for_name("LazyHashState")],
      )
      converter.__test_lower_function_if_needed(target_name)

      target = converter.module.function_by_name(target_name)
      target.should_not be_nil
      text = hir_text(target.not_nil!)
      text.should contain("literal 7")
      text.should_not contain("literal 9")
    end

    it "repairs a zero-positional block target from a transitive generic inclusion" do
      previous = ENV["ADAMAS_DISABLE_INLINE_YIELD"]?
      ENV["ADAMAS_DISABLE_INLINE_YIELD"] = "1"
      begin
        converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
          module LazyAnyLike(T)
            def any?(& : T ->) : Bool
              each { |value| return true if yield value }
              false
            end
          end

          module LazyEnumerableLike(T)
            include LazyAnyLike(T)
          end

          class LazyAnyIterator(T)
            include LazyEnumerableLike(T)

            def each(& : T ->) : Nil
              yield uninitialized T
            end
          end

          LazyAnyIterator(Int32).new.any? { |value| value > 0 }
        CRYSTAL

        main = converter.module.function_by_name("__adamas_main")
        main.should_not be_nil
        before_repair = main.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
          instruction.as?(Adamas::HIR::Call)
        end.find { |call| call.method_name.includes?("#any?") }
        before_repair.should_not be_nil, hir_text(main.not_nil!)
        before_repair.not_nil!.args.size.should eq(1)
        before_repair.not_nil!.has_block?.should be_true
        before_repair.not_nil!.method_name.should eq(
          "LazyAnyIterator(Int32)#any?$block"
        )
        stale_name = "LazyAnyIterator(Int32)#any?$Proc_block"
        before_repair.not_nil!.method_name = stale_name
        converter.module.remove_function(stale_name)
        converter.__test_reset_lowering_state(stale_name)

        converter.__test_repair_receiver_bound_call_targets

        repaired_name = main.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
          instruction.as?(Adamas::HIR::Call).try(&.method_name)
        end.find { |name| name.includes?("#any?") }
        repaired_name.should_not be_nil, hir_text(main.not_nil!)
        repaired_name.not_nil!.should eq("LazyAnyIterator(Int32)#any?$block")
        target = converter.module.function_by_name(repaired_name.not_nil!)
        target.should_not be_nil
        target.not_nil!.blocks.any? { |block| !block.instructions.empty? }.should be_true
      ensure
        if previous
          ENV["ADAMAS_DISABLE_INLINE_YIELD"] = previous
        else
          ENV.delete("ADAMAS_DISABLE_INLINE_YIELD")
        end
      end
    end

    it "preserves a real Proc argument while repairing a block target" do
      previous = ENV["ADAMAS_DISABLE_INLINE_YIELD"]?
      ENV["ADAMAS_DISABLE_INLINE_YIELD"] = "1"
      begin
        converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
          class ProcAndBlockIterator(T)
            def select(predicate : Proc(T, Bool), & : T ->) : Bool
              false
            end
          end

          predicate = ->(value : Int32) { value > 0 }
          ProcAndBlockIterator(Int32).new.select(predicate) { |value| value > 1 }
        CRYSTAL

        main = converter.module.function_by_name("__adamas_main")
        main.should_not be_nil
        call = main.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
          instruction.as?(Adamas::HIR::Call)
        end.find { |candidate| candidate.method_name.includes?("#select") }
        call.should_not be_nil, hir_text(main.not_nil!)
        call.not_nil!.args.size.should eq(2)
        call.not_nil!.has_block?.should be_true
        original_name = call.not_nil!.method_name
        original_name.should contain("ProcAndBlockIterator(Int32)#select")
        original_name.should end_with("$Proc_block")
        converter.module.remove_function(original_name)
        converter.__test_reset_lowering_state(original_name)

        converter.__test_repair_receiver_bound_call_targets

        call.not_nil!.method_name.should eq(original_name)
        target = converter.module.function_by_name(original_name)
        target.should_not be_nil
        target.not_nil!.blocks.any? { |block| !block.instructions.empty? }.should be_true
      ensure
        if previous
          ENV["ADAMAS_DISABLE_INLINE_YIELD"] = previous
        else
          ENV.delete("ADAMAS_DISABLE_INLINE_YIELD")
        end
      end
    end

    it "resolves a bare included method registered after generic monomorphization" do
      source = <<-CRYSTAL
        module EnumerableLike(T)
        end

        module IndexableLike(T)
          include EnumerableLike(T)
        end

        class Bag(T)
          include IndexableLike(T)

          def uniq
            to_set
          end
        end

        module EnumerableLike(T)
          def to_set : Int32
            7
          end
        end
      CRYSTAL
      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
      converter.arena = arena
      modules = exprs.compact_map { |id| arena[id].as?(Adamas::Compiler::Frontend::ModuleNode) }
      bag = exprs.compact_map { |id| arena[id].as?(Adamas::Compiler::Frontend::ClassNode) }.first

      converter.register_module(modules[0])
      converter.register_module(modules[1])
      converter.register_class(bag)
      converter.__test_monomorphize_generic_class("Bag", ["UInt32"], "Bag(UInt32)")
      converter.register_module(modules[2])
      converter.__test_lower_function_if_needed("Bag(UInt32)#uniq")

      func = converter.module.function_by_name("Bag(UInt32)#uniq")
      func.should_not be_nil
      text = hir_text(func.not_nil!)
      text.should contain("Bag(UInt32)#to_set")
      text.should_not contain("local \"to_set\" : 0")
      text.should_not contain("local \"to_set\" : Void")
    end

    it "keeps bare and explicit included-module calls equivalent after an array intrinsic" do
      converter = lower_program_with_main(<<-CRYSTAL)
        module OwnerTail(T)
          def tail_value : Int32
            7
          end
        end

        class OwnerProbe(T)
          include OwnerTail(T)

          def bare
            ary = Array(T).new
            ary.each { |elem| elem }
            tail_value
          end

          def explicit
            ary = Array(T).new
            ary.each { |elem| elem }
            self.tail_value
          end
        end

        probe = OwnerProbe(UInt32).new
        probe.bare
        probe.explicit
      CRYSTAL

      converter.__test_lower_function_if_needed("OwnerProbe(UInt32)#bare")
      converter.__test_lower_function_if_needed("OwnerProbe(UInt32)#explicit")

      bare = converter.module.function_by_name("OwnerProbe(UInt32)#bare")
      explicit = converter.module.function_by_name("OwnerProbe(UInt32)#explicit")
      bare.should_not be_nil
      explicit.should_not be_nil
      bare_text = hir_text(bare.not_nil!)
      explicit_text = hir_text(explicit.not_nil!)
      bare_text.should contain("OwnerProbe(UInt32)#tail_value")
      explicit_text.should contain("OwnerProbe(UInt32)#tail_value")
      bare_text.should_not contain("local \"tail_value\" : 0")

      converter.__test_lower_function_if_needed("OwnerProbe(UInt32)#tail_value")
      tail = converter.module.function_by_name("OwnerProbe(UInt32)#tail_value")
      tail.should_not be_nil
      tail.not_nil!.blocks.any? { |block| !block.instructions.empty? }.should be_true
    end

    it "does not bind a generic module self call to the only already-lowered includer" do
      converter = lower_program_with_main(<<-CRYSTAL)
        module StaticDispatchControl
          def self.marker : Int32
            7
          end

          def self.via_self : Int32
            self.marker
          end
        end

        enum DispatchEnum
          A
        end

        module DispatchRoot(T)
          abstract def size : Int32
          abstract def unsafe_fetch(index : Int32) : T
          abstract def unsafe_put(index : Int32, value : T)
          abstract def classify(value : Int32) : Int32
          abstract def classify(value : String) : String
        end

        module DispatchRoot::Mutable(T)
          include DispatchRoot(T)

          def self.size : Int32
            99
          end

          def swap(index0 : Int32, index1 : Int32) : self
            tmp = unsafe_fetch(index0)
            unsafe_put(index0, unsafe_fetch(index1))
            unsafe_put(index1, tmp)
            self
          end

          def explicit_fetch(index : Int32) : T
            self.unsafe_fetch(index)
          end

          def grouped_fetch(index : Int32) : T
            (self).unsafe_fetch(index)
          end

          def explicit_size : Int32
            self.size
          end

          def grouped_size : Int32
            (self).size
          end

          def explicit_classify(value : Int32) : Int32
            self.classify(value)
          end

          def default_probe(value : Int32 = 17) : Int32
            value
          end

          def explicit_default_probe : Int32
            self.default_probe
          end

          def explicit_module_marker : Int32
            StaticDispatchControl.marker
          end
        end

        class Materialized(T)
          include DispatchRoot::Mutable(T)

          def unsafe_fetch(index : Int32) : T
            uninitialized T
          end

          def unsafe_put(index : Int32, value : T)
          end

          def size : Int32
            1
          end

          def classify(value : Int32) : Int32
            value
          end

          def classify(value : String) : String
            value
          end

          def default_probe(value : Int32 = 99) : Int32
            value
          end
        end

        Materialized(Int32).new.unsafe_fetch(0)
      CRYSTAL

      converter.__test_monomorphize_generic_class(
        "DispatchRoot::Mutable",
        ["Int32"],
        "DispatchRoot::Mutable(Int32)",
      )
      module_desc = Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Generic,
        "DispatchRoot::Mutable(Int32)",
        [Adamas::HIR::TypeRef::INT32],
      )
      module_ref = converter.module.intern_type(module_desc)
      converter.module.types.each_with_index do |desc, index|
        converter.module.types[index] = module_desc if desc.name == module_desc.name
      end
      converter.__test_register_virtual_repair_class_info(
        "DispatchRoot::Mutable(Int32)",
        module_ref,
        false,
      )
      converter.__test_lower_function_if_needed(
        "DispatchRoot::Mutable(Int32)#swap$Int32_Int32",
      )
      converter.__test_lower_function_if_needed(
        "DispatchRoot::Mutable(Int32)#explicit_fetch$Int32",
      )
      converter.__test_lower_function_if_needed(
        "DispatchRoot::Mutable(Int32)#grouped_fetch$Int32",
      )
      converter.__test_lower_function_if_needed(
        "DispatchRoot::Mutable(Int32)#explicit_size",
      )
      converter.__test_lower_function_if_needed(
        "DispatchRoot::Mutable(Int32)#grouped_size",
      )
      converter.__test_lower_function_if_needed(
        "DispatchRoot::Mutable(Int32)#explicit_classify$Int32",
      )
      converter.__test_lower_function_if_needed(
        "DispatchRoot::Mutable(Int32)#explicit_default_probe",
      )
      converter.__test_lower_function_if_needed(
        "DispatchRoot::Mutable(Int32)#explicit_module_marker",
      )
      converter.__test_lower_function_if_needed("StaticDispatchControl.via_self")

      swap = converter.module.functions.find do |func|
        func.name.starts_with?("DispatchRoot::Mutable(Int32)#swap")
      end
      explicit_fetch = converter.module.functions.find do |func|
        func.name.starts_with?("DispatchRoot::Mutable(Int32)#explicit_fetch")
      end
      grouped_fetch = converter.module.functions.find do |func|
        func.name.starts_with?("DispatchRoot::Mutable(Int32)#grouped_fetch")
      end
      explicit_size = converter.module.functions.find do |func|
        func.name.starts_with?("DispatchRoot::Mutable(Int32)#explicit_size")
      end
      grouped_size = converter.module.functions.find do |func|
        func.name.starts_with?("DispatchRoot::Mutable(Int32)#grouped_size")
      end
      explicit_classify = converter.module.functions.find do |func|
        func.name.starts_with?("DispatchRoot::Mutable(Int32)#explicit_classify")
      end
      explicit_default_probe = converter.module.functions.find do |func|
        func.name.starts_with?("DispatchRoot::Mutable(Int32)#explicit_default_probe")
      end
      explicit_module_marker = converter.module.functions.find do |func|
        func.name.starts_with?("DispatchRoot::Mutable(Int32)#explicit_module_marker")
      end
      static_via_self = converter.module.functions.find do |func|
        func.name.starts_with?("StaticDispatchControl.via_self")
      end
      swap.should_not be_nil
      explicit_fetch.should_not be_nil
      grouped_fetch.should_not be_nil
      explicit_size.should_not be_nil
      grouped_size.should_not be_nil
      explicit_classify.should_not be_nil
      explicit_default_probe.should_not be_nil
      explicit_module_marker.should_not be_nil
      static_via_self.should_not be_nil

      functions = [
        swap.not_nil!,
        explicit_fetch.not_nil!,
        grouped_fetch.not_nil!,
        explicit_size.not_nil!,
        grouped_size.not_nil!,
        explicit_classify.not_nil!,
        explicit_default_probe.not_nil!,
      ]
      text = functions.map { |func| hir_text(func) }.join('\n')
      text.should contain("DispatchRoot::Mutable(Int32)#unsafe_fetch")
      text.should contain("DispatchRoot::Mutable(Int32)#unsafe_put")
      text.should contain("DispatchRoot::Mutable(Int32)#size")
      text.should contain("DispatchRoot::Mutable(Int32)#classify$Int32")
      text.should contain("DispatchRoot::Mutable(Int32)#default_probe$Int32")
      text.should_not contain("Materialized(Int32)#unsafe_fetch")
      text.should_not contain("Materialized(Int32)#unsafe_put")
      text.should_not contain("Materialized(Int32)#size")
      text.should_not contain("Materialized(Int32)#classify")
      text.should_not contain("Materialized(Int32)#default_probe")

      dispatch_calls = functions.flat_map(&.blocks).flat_map(&.instructions).compact_map do |instruction|
        call = instruction.as?(Adamas::HIR::Call)
        call if call && (
          call.method_name.includes?("#unsafe_fetch") ||
          call.method_name.includes?("#unsafe_put") ||
          call.method_name.includes?("#size") ||
          call.method_name.includes?("#classify") ||
          call.method_name.includes?("#default_probe")
        )
      end
      dispatch_calls.should_not be_empty
      dispatch_calls.each { |call| call.virtual.should be_true }
      dispatch_calls.select { |call| call.method_name.includes?("#unsafe_fetch") }
        .each { |call| call.type.should eq(Adamas::HIR::TypeRef::INT32) }

      static_text = [
        hir_text(explicit_module_marker.not_nil!),
        hir_text(static_via_self.not_nil!),
      ].join('\n')
      static_text.should contain("StaticDispatchControl.marker")
      static_text.should_not contain("StaticDispatchControl#marker")
    end

    it "keeps included zero-arg receiver calls bound to the inferred owner type" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class WrongType
          def type
            99
          end
        end

        struct InfoType
          def pipe?
            true
          end
        end

        struct Info
          def type
            InfoType.new
          end
        end

        module HasInfo
          def system_info
            Info.new
          end
        end

        class Box
          include HasInfo

          def foo
            case system_info.type
            when .pipe?
              1
            else
              2
            end
          end
        end

        Box.new.foo
      CRYSTAL

      converter.__test_lower_function_if_needed("Box#foo")

      func = converter.module.function_by_name("Box#foo")
      func.should_not be_nil

      text = hir_text(func.not_nil!)
      text.should contain("Box#system_info")
      text.should contain("Info#type")
      text.should_not contain("WrongType#type")
    end

    it "materializes repaired nested zero-arg receiver callees from included modules" do
      converter = lower_program_with_main(<<-CRYSTAL)
        module HasSystemType
          def system_type
            7
          end
        end

        struct Info
          include HasSystemType

          def type
            system_type
          end
        end

        class Box
          def foo
            Info.new.type
          end
        end

        Box.new.foo
      CRYSTAL

      converter.__test_lower_function_if_needed("Box#foo")

      type_func = converter.module.function_by_name("Info#type")
      type_func.should_not be_nil
      hir_text(type_func.not_nil!).should contain("Info#system_type")

      system_type_func = converter.module.function_by_name("Info#system_type")
      system_type_func.should_not be_nil
      system_type_func.not_nil!.blocks.any? { |block| !block.instructions.empty? }.should be_true
    end

    it "materializes nested namespaced zero-arg receiver callees from included modules" do
      converter = lower_program_with_main(<<-CRYSTAL)
        module Crystal::System::FileInfo
          def system_type
            7
          end
        end

        class File
          struct Info
            include Crystal::System::FileInfo

            def type
              system_type
            end
          end
        end

        class Box
          def foo
            File::Info.new.type
          end
        end

        Box.new.foo
      CRYSTAL

      converter.__test_lower_function_if_needed("Box#foo")

      type_func = converter.module.function_by_name("File::Info#type")
      type_func.should_not be_nil
      hir_text(type_func.not_nil!).should contain("File::Info#system_type")

      system_type_func = converter.module.function_by_name("File::Info#system_type")
      system_type_func.should_not be_nil
      system_type_func.not_nil!.blocks.any? { |block| !block.instructions.empty? }.should be_true
    end

    it "drains pending nested receiver callees after late included-call repair" do
      converter = lower_program_with_main(<<-CRYSTAL)
        module Crystal::System::FileInfo
          def system_type
            7
          end
        end

        class File
          struct Info
            include Crystal::System::FileInfo

            def type
              system_type
            end
          end
        end

        module HasInfo
          def system_info
            File::Info.new
          end
        end

        class Box
          include HasInfo

          def foo
            system_info.type
          end
        end

        Box.new.foo
      CRYSTAL

      type_func = converter.module.function_by_name("File::Info#type")
      type_func.should_not be_nil
      hir_text(type_func.not_nil!).should contain("File::Info#system_type")

      system_type_func = converter.module.function_by_name("File::Info#system_type")
      system_type_func.should_not be_nil
      system_type_func.not_nil!.blocks.any? { |block| !block.instructions.empty? }.should be_true
    end

    it "rebinds consumer overloads after nested call return types are repaired" do
      converter = lower_program_with_main(<<-CRYSTAL)
        struct Point
          property val : Float64
          property ts : Int64

          def initialize(@val : Float64, @ts : Int64)
          end
        end

        puts [Point.new(1.0, 2_i64)].inspect
      CRYSTAL

      main = converter.module.function_by_name("__adamas_main")
      main.should_not be_nil

      text = hir_text(main.not_nil!)
      text.should contain("Array(Point)#inspect() : 15")
      text.should contain("__adamas_print_string_ln")
      text.should_not contain("IO#puts$Nil")
    end

    it "orders dependent deferred constants after their referenced constants" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class H
          HASH_BITS = begin
            61
          end
          HASH_MODULUS = (1_i64 << HASH_BITS) - 1
        end

        def run
          H::HASH_MODULUS
        end

        run()
      CRYSTAL

      main = converter.module.function_by_name("__adamas_main")
      main.should_not be_nil

      text = hir_text(main.not_nil!)
      bits_idx = text.index("classvar_set H.@@HASH_BITS")
      bits_idx.should_not be_nil
      modulus_idx = text.index("classvar_set H.@@HASH_MODULUS")
      modulus_idx.should_not be_nil
      bits_idx.not_nil!.should be < modulus_idx.not_nil!
    end

    it "keeps unqualified class-method calls inside deferred constant initializers" do
      converter = lower_program_with_main(<<-CRYSTAL)
        module DeferredConstantCall
          def record : Nil
          end

          def self.record(values : Array(Int32), value : Int32) : Nil
            values << value
          end

          VALUES = begin
            values = Array(Int32).new
            7.as(Int32?).try { |value| record(values, value) }
            values
          end
        end

        def consume_deferred_values(values : Array(Int32))
          values
        end

        consume_deferred_values(DeferredConstantCall::VALUES)
      CRYSTAL

      main = converter.module.function_by_name("__adamas_main")
      main.should_not be_nil
      main_text = hir_text(main.not_nil!)
      main_text.should contain("DeferredConstantCall.record$Array(Int32)_Int32")
      main_text.should_not contain("DeferredConstantCall#record")
      main_text.should contain("union_unwrap")
      main_text.should_not contain("local \"self\"")

      record = converter.module.function_by_name("DeferredConstantCall.record$Array(Int32)_Int32")
      record.should_not be_nil
      hir_text(record.not_nil!).should contain("Array(Int32)#<<$Int32")
    end

    it "keeps source order for unrelated deferred constants instead of preferring deeper namespaces" do
      converter = lower_program_with_sources(<<-CRYSTAL)
        class H
          FIRST = {1, 2}
        end

        class Outer
          class Inner
            DEEP = {1, 2}
          end
        end

      CRYSTAL

      deferred_names = converter.__test_sorted_deferred_constant_init_names
      first_idx = deferred_names.index("FIRST")
      first_idx.should_not be_nil
      deep_idx = deferred_names.index("DEEP")
      deep_idx.should_not be_nil
      first_idx.not_nil!.should be < deep_idx.not_nil!
    end

    it "registers a nested class deferred classvar initializer once" do
      arena, exprs = parse(<<-CRYSTAL)
        module RuntimeInitOwner
          class Nested
            @@STATE = build_state
          end
        end
      CRYSTAL
      converter = Adamas::HIR::AstToHir.new(arena)
      converter.arena = arena
      module_expr = exprs.find { |expr_id| arena[expr_id].is_a?(Adamas::Compiler::Frontend::ModuleNode) }
      module_expr.should_not be_nil
      module_node = arena[module_expr.not_nil!].as(Adamas::Compiler::Frontend::ModuleNode)

      converter.register_module(module_node)

      converter.__test_deferred_classvar_init_names.count("STATE").should eq(1)
    end

    it "keeps typed super dispatch flags out of parsed callsite arg types" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class Exception
          def initialize(@message : String? = nil, @cause : Exception? = nil)
          end
        end

        class ArgumentError < Exception
          def initialize(message = "Argument error")
            super(message)
          end
        end

        ArgumentError.new("boom")
      CRYSTAL

      converter.__test_lower_function_if_needed("ArgumentError#initialize$String")
      typed_init = converter.module.function_by_name("ArgumentError#initialize$String")
      typed_init.should_not be_nil
      typed_text = hir_text(typed_init.not_nil!)
      typed_text.should contain("Exception#initialize")
      typed_text.should contain("_super")
      typed_text.should_not contain("call %0.ArgumentError#initialize(")
    end

    it "does not retarget super-tagged exception initialize wrappers back to self" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class Exception
          def initialize(@message : String? = nil, @cause : Exception? = nil)
          end
        end

        class ArgumentError < Exception
          def initialize(message = "Argument error")
            super(message)
          end
        end

        arg = ArgumentError.new("boom")
        arg.message
      CRYSTAL

      converter.__test_lower_function_if_needed("ArgumentError#initialize")

      base_init = converter.module.function_by_name("ArgumentError#initialize")
      base_init.should_not be_nil
      base_text = hir_text(base_init.not_nil!)
      base_text.should contain("Exception#initialize")
      base_text.should contain("_super")
      base_text.should_not contain("call %0.ArgumentError#initialize(")
    end

    it "backfills partial untyped default-arg call types from recorded history before lowering" do
      arena, exprs = parse(<<-CRYSTAL)
        def wait_like(io, timeout = nil)
          io.to_s
        end
      CRYSTAL

      converter = Adamas::HIR::AstToHir.new(arena)
      converter.arena = arena

      def_expr = exprs.find { |expr_id| arena[expr_id].is_a?(Adamas::Compiler::Frontend::DefNode) }
      def_expr.should_not be_nil
      def_node = arena[def_expr.not_nil!].as(Adamas::Compiler::Frontend::DefNode)

      converter.register_function(def_node)

      int32_ref = converter.__test_type_ref_for_name("Int32")
      nil_ref = Adamas::HIR::TypeRef::NIL
      partial = [Adamas::HIR::TypeRef::VOID, nil_ref]

      converter.__test_missing_required_runtime_param_types?(def_node, partial).should be_true
      converter.__test_remember_callsite_arg_types("wait_like", [int32_ref, nil_ref])

      repaired = converter.__test_repair_partial_untyped_call_types_from_history("wait_like", def_node, partial)
      repaired.should eq([int32_ref, nil_ref])
      converter.__test_missing_required_runtime_param_types?(def_node, repaired).should be_false
    end

    it "keeps visibility-wrapped private constants reachable in deferred init bookkeeping" do
      arena, exprs = parse(<<-CRYSTAL)
        class Box
          private C1 = 11_i64

          def value
            C1
          end
        end
      CRYSTAL

      converter = Adamas::HIR::AstToHir.new(arena)
      converter.arena = arena

      class_expr = exprs.find { |expr_id| arena[expr_id].is_a?(Adamas::Compiler::Frontend::ClassNode) }
      class_expr.should_not be_nil
      class_node = arena[class_expr.not_nil!].as(Adamas::Compiler::Frontend::ClassNode)

      converter.register_class(class_node)
      converter.lower_class(class_node)

      converter.__test_deferred_classvar_init_names.should contain("C1")
    end

    it "preserves high-bit UInt64 private constant literals instead of zeroing them" do
      converter = lower_program_with_main(<<-CRYSTAL)
        struct X
          private C1 = 0xacd5ad43274593b9_u64

          def self.c1
            C1
          end
        end

        X.c1
      CRYSTAL

      converter.__test_constant_literal_int_value("X::C1").should eq(0xacd5ad43274593b9_u64.unsafe_as(Int64))
    end

    it "does not borrow a source literal from the same constant name in another owner" do
      converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
        class AggregateOwner
          VALUES = {} of String => String
        end

        class CallOwner
          VALUES = build_values
        end

        class ScalarOwner
          VALUES = 7
        end
      CRYSTAL

      converter.__test_constant_literal_int_value("AggregateOwner::VALUES").should be_nil
      converter.__test_constant_literal_int_value("CallOwner::VALUES").should be_nil
      converter.__test_constant_literal_int_value("ScalarOwner::VALUES").should eq(7_i64)
    end

    it "inlines enum predicates through zero-arg enum-returning calls" do
      converter = lower_program_with_main(<<-CRYSTAL)
        enum FileType : UInt8
          File
          Pipe
        end

        class Info
          def type : FileType
            FileType::Pipe
          end
        end

        class Box
          def foo(info : Info)
            info.type.pipe?
          end
        end

        Box.new.foo(Info.new)
      CRYSTAL

      converter.__test_lower_function_if_needed("Box#foo$Info")

      foo = converter.module.function_by_name("Box#foo$Info")
      foo.should_not be_nil
      text = hir_text(foo.not_nil!)
      text.should contain("binop Eq")
      text.should_not contain(".pipe?()")
    end

    it "records enum return identity for typed property getters" do
      converter = lower_program_with_main(<<-CRYSTAL)
        enum FileType
          File
          Pipe
        end

        class Info
          property type : FileType

          def initialize(@type : FileType)
          end
        end

        Info.new(FileType::Pipe).type
      CRYSTAL

      converter.__test_enum_return_name_for("Info#type").should eq("FileType")
    end

    it "clears generated enum accessor identity when an explicit method replaces it" do
      converter = lower_program_with_main(<<-CRYSTAL)
        enum FileType
          File
          Pipe
        end

        class Info
          property type : FileType
        end

        class Info
          def type : Int32
            7
          end
        end

        Info.new.type
      CRYSTAL

      converter.__test_enum_return_name_for("Info#type").should be_nil
    end

    it "lazily resolves sibling enum identity for typed property getters registered before the enum" do
      arena, exprs = parse(<<-CRYSTAL)
        class Info
          property type : Type
        end

        enum Type
          File
          Pipe
        end
      CRYSTAL
      converter = Adamas::HIR::AstToHir.new(arena)
      converter.arena = arena

      class_expr = exprs.find { |expr_id| arena[expr_id].is_a?(Adamas::Compiler::Frontend::ClassNode) }
      enum_expr = exprs.find { |expr_id| arena[expr_id].is_a?(Adamas::Compiler::Frontend::EnumNode) }
      class_node = arena[class_expr.not_nil!].as(Adamas::Compiler::Frontend::ClassNode)
      enum_node = arena[enum_expr.not_nil!].as(Adamas::Compiler::Frontend::EnumNode)

      converter.__test_register_class_with_name(class_node, "Outer::Info")
      converter.__test_register_enum_with_name(enum_node, "Outer::Type")

      converter.__test_enum_return_name_for("Outer::Info#type").should eq("Outer::Type")
    end

    it "resolves generated enum accessors through nilable union receivers" do
      source = <<-CRYSTAL
        class Outer
          class Info
            property kind : FileType
          end
        end

        class Registry
          def get : Outer::Info?
            nil
          end

          def check
            get.kind.tuple?
          end
        end

        enum FileType
          Other
          Tuple
        end
      CRYSTAL

      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
      converter.arena = arena

      outer_expr = exprs.find do |expr_id|
        node = arena[expr_id]
        node.is_a?(Adamas::Compiler::Frontend::ClassNode) &&
          String.new(node.as(Adamas::Compiler::Frontend::ClassNode).name.not_nil!) == "Outer"
      end
      registry_expr = exprs.find do |expr_id|
        node = arena[expr_id]
        node.is_a?(Adamas::Compiler::Frontend::ClassNode) &&
          String.new(node.as(Adamas::Compiler::Frontend::ClassNode).name.not_nil!) == "Registry"
      end
      enum_expr = exprs.find { |expr_id| arena[expr_id].is_a?(Adamas::Compiler::Frontend::EnumNode) }
      outer_node = arena[outer_expr.not_nil!].as(Adamas::Compiler::Frontend::ClassNode)
      registry_node = arena[registry_expr.not_nil!].as(Adamas::Compiler::Frontend::ClassNode)
      enum_node = arena[enum_expr.not_nil!].as(Adamas::Compiler::Frontend::EnumNode)

      # Force the generated getter to be registered before its enum declaration.
      converter.register_class(outer_node)
      converter.register_enum(enum_node)
      resolved_name = converter.__test_resolve_union_method_call("Nil | Outer::Info", "kind")
      resolved_name.should eq("Outer::Info#kind")
      resolved_type = converter.__test_get_function_return_type(resolved_name.not_nil!)
      converter.__test_get_type_name_from_ref(resolved_type).should eq("FileType")
      converter.register_class(registry_node)

      check_name = converter.__test_function_def_names("Registry#check").first?
      check_name.should_not be_nil
      converter.__test_lower_function_if_needed(check_name.not_nil!)
      check = converter.module.function_by_name(check_name.not_nil!)
      check.should_not be_nil
      text = hir_text(check.not_nil!)
      text.should contain("Outer::Info#kind")
      text.should contain("binop Eq")
      text.should_not contain(".tuple?()")
    end

    it "does not admit bodyless zero-arg union methods as generated accessors" do
      source = <<-CRYSTAL
        class Outer
          class Info
          end
        end
      CRYSTAL
      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
      converter.arena = arena
      outer_expr = exprs.find { |expr_id| arena[expr_id].is_a?(Adamas::Compiler::Frontend::ClassNode) }
      outer_node = arena[outer_expr.not_nil!].as(Adamas::Compiler::Frontend::ClassNode)
      converter.register_class(outer_node)

      converter.__test_register_function_type("Outer::Info#bodyless", Adamas::HIR::TypeRef::BOOL)
      converter.__test_resolve_union_method_call("Nil | Outer::Info", "bodyless").should be_nil
    end

    it "preserves enum identity across ternary branches for enum predicates" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class Box
          enum Kind
            Other
            Tuple
          end

          def check(flag : Bool)
            (flag ? Kind::Tuple : Kind::Other).tuple?
          end
        end

        Box.new.check(true)
      CRYSTAL

      converter.__test_lower_function_if_needed("Box#check$Bool")
      check = converter.module.function_by_name("Box#check$Bool")
      check.should_not be_nil
      text = hir_text(check.not_nil!)
      text.should contain("binop Eq")
      text.should_not contain(".tuple?()")
    end

    it "does not transfer enum identity across mixed ternary enum branches" do
      converter = lower_program_with_main(<<-CRYSTAL)
        enum LeftType
          Other
          Tuple
        end

        enum RightType
          Other
          Tuple
        end

        class Box
          def check(flag : Bool)
            (flag ? LeftType::Tuple : RightType::Tuple).tuple?
          end
        end

        Box.new.check(true)
      CRYSTAL

      converter.__test_lower_function_if_needed("Box#check$Bool")
      check = converter.module.function_by_name("Box#check$Bool")
      check.should_not be_nil
      text = hir_text(check.not_nil!)
      text.should_not contain("binop Eq")
      text.should contain("Int32#tuple?()")
    end

    it "inlines enum predicates in case-dot-when branches over enum-returning calls" do
      converter = lower_program_with_main(<<-CRYSTAL)
        enum FileType : UInt8
          File
          Pipe
          Socket
        end

        class Info
          def type : FileType
            FileType::Pipe
          end
        end

        class Box
          def foo(info : Info)
            case info.type
            when .pipe?, .socket?
              1
            else
              2
            end
          end
        end

        Box.new.foo(Info.new)
      CRYSTAL

      converter.__test_lower_function_if_needed("Box#foo$Info")

      foo = converter.module.function_by_name("Box#foo$Info")
      foo.should_not be_nil
      text = hir_text(foo.not_nil!)
      text.should contain("binop Eq")
      text.should_not contain(".pipe?()")
      text.should_not contain(".socket?()")
    end

    it "inlines enum predicates in case-dot-when branches over nested receiver calls" do
      converter = lower_program_with_main(<<-CRYSTAL)
        enum FileType : UInt8
          File
          Pipe
          Socket
        end

        class Info
          def type : FileType
            FileType::Pipe
          end
        end

        module HasInfo
          def system_info
            Info.new
          end
        end

        class Box
          include HasInfo

          def foo
            case system_info.type
            when .pipe?, .socket?
              1
            else
              2
            end
          end
        end

        Box.new.foo
      CRYSTAL

      converter.__test_lower_function_if_needed("Box#foo")

      foo = converter.module.function_by_name("Box#foo")
      foo.should_not be_nil
      text = hir_text(foo.not_nil!)
      text.should contain("Box#system_info")
      text.should contain("Info#type")
      text.should contain("binop Eq")
      text.should_not contain(".pipe?()")
      text.should_not contain(".socket?()")
    end

    it "inlines case-dot-when predicates for nested enum owners with shorthand return annotations" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class File
          enum Type : UInt8
            File
            Pipe
            Socket
          end

          class Info
            def type : Type
              Type::Pipe
            end
          end
        end

        module HasInfo
          def system_info
            File::Info.new
          end
        end

        class Box
          include HasInfo

          def foo
            case system_info.type
            when .pipe?, .socket?
              1
            else
              2
            end
          end
        end

        Box.new.foo
      CRYSTAL

      converter.__test_lower_function_if_needed("Box#foo")

      foo = converter.module.function_by_name("Box#foo")
      foo.should_not be_nil
      text = hir_text(foo.not_nil!)
      text.should contain("File::Info#type")
      text.should contain("binop Eq")
      text.should_not contain(".pipe?()")
      text.should_not contain(".socket?()")
    end

    it "inlines case-dot-when predicates through enum-returning forwarding methods" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class File
          enum Type : UInt8
            File
            Pipe
            Socket
          end

          class Info
            def type : Type
              system_type
            end

            def system_type : Type
              Type::Pipe
            end
          end
        end

        module HasInfo
          def system_info
            File::Info.new
          end
        end

        class Box
          include HasInfo

          def foo
            case system_info.type
            when .pipe?, .socket?
              1
            else
              2
            end
          end
        end

        Box.new.foo
      CRYSTAL

      converter.__test_lower_function_if_needed("Box#foo")

      foo = converter.module.function_by_name("Box#foo")
      foo.should_not be_nil
      text = hir_text(foo.not_nil!)
      text.should contain("File::Info#type")
      text.should contain("binop Eq")
      text.should_not contain(".pipe?()")
      text.should_not contain(".socket?()")
    end

    it "inlines case-dot-when predicates through enum-returning forwarding methods on structs" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class File
          enum Type : UInt8
            File
            Pipe
            Socket
          end

          struct Info
            def type : Type
              system_type
            end

            def system_type : Type
              Type::Pipe
            end
          end
        end

        module HasInfo
          def system_info
            File::Info.new
          end
        end

        class Box
          include HasInfo

          def foo
            case system_info.type
            when .pipe?, .socket?
              1
            else
              2
            end
          end
        end

        Box.new.foo
      CRYSTAL

      converter.__test_lower_function_if_needed("Box#foo")

      foo = converter.module.function_by_name("Box#foo")
      foo.should_not be_nil
      text = hir_text(foo.not_nil!)
      text.should contain("File::Info#type")
      text.should contain("binop Eq")
      text.should_not contain(".pipe?()")
      text.should_not contain(".socket?()")
    end

    it "inlines case-dot-when predicates through included-module enum forwarders on structs" do
      converter = lower_program_with_main(<<-CRYSTAL)
        module Crystal::System::FileInfo
          def system_type : ::File::Type
            ::File::Type::Pipe
          end
        end

        class File
          enum Type : UInt8
            File
            Pipe
            Socket
          end

          struct Info
            include Crystal::System::FileInfo

            def type : Type
              system_type
            end
          end
        end

        module HasInfo
          def system_info
            File::Info.new
          end
        end

        class Box
          include HasInfo

          def foo
            case system_info.type
            when .pipe?, .socket?
              1
            else
              2
            end
          end
        end

        Box.new.foo
      CRYSTAL

      converter.__test_lower_function_if_needed("Box#foo")

      foo = converter.module.function_by_name("Box#foo")
      foo.should_not be_nil
      text = hir_text(foo.not_nil!)
      text.should contain("File::Info#type")
      text.should contain("binop Eq")
      text.should_not contain(".pipe?()")
      text.should_not contain(".socket?()")
    end
  end

  describe "macro literal parameter filtering" do
    it "drops inactive inline flag-controlled params inside begin-wrapped class bodies" do
      converter = lower_program_with_sources(<<-CRYSTAL)
        class Outer
          {% begin %}
          def self.wrap(x : Int32{% if flag?(:execution_context) %}, y : String = "bad"{% end %}, &block)
            block.call
          end
          {% end %}
        end

        Outer.wrap(1) { 42 }
      CRYSTAL

      main = converter.module.function_by_name("__adamas_main")
      main.should_not be_nil

      text = hir_text(main.not_nil!)
      text.should contain("call Outer.wrap$Int32_block")
      text.should_not contain("Outer.wrap$Int32_String_block")
      text.should_not contain(%("bad"))
    end
  end

  describe "branch condition return inference" do
    it "preserves the nilable tuple element when branch locals come from condition assignments" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class Worker
          def initialize(@queue : Array(Int32)?, @fallback : Int32?)
          end

          def pick
            if (q = @queue) && !q.empty?
              value = q.first
              {1, value}
            elsif other = @fallback
              value = other
              {1, value}
            else
              {0, nil}
            end
          end

          def use
            state, value = pick
            {state, value}
          end
        end

        Worker.new([1], 2).use
      CRYSTAL

      use_func = converter.module.functions.find { |func| func.name.starts_with?("Worker#use") }
      use_func.should_not be_nil

      pick_call = use_func.not_nil!.blocks.flat_map(&.instructions).find do |inst|
        inst.is_a?(Adamas::HIR::Call) && inst.as(Adamas::HIR::Call).method_name.starts_with?("Worker#pick")
      end
      pick_call.should_not be_nil

      call_type = pick_call.not_nil!.as(Adamas::HIR::Call).type
      call_desc = converter.module.get_type_descriptor(call_type)
      call_desc.should_not be_nil
      call_desc.not_nil!.kind.should eq(Adamas::HIR::TypeKind::Tuple)
      call_desc.not_nil!.type_params.size.should eq(2)
      call_desc.not_nil!.type_params[0].should eq(Adamas::HIR::TypeRef::INT32)

      value_desc = converter.module.get_type_descriptor(call_desc.not_nil!.type_params[1])
      value_desc.should_not be_nil
      value_desc.not_nil!.kind.should eq(Adamas::HIR::TypeKind::Union)
      value_desc.not_nil!.name.should contain("Int32")
      value_desc.not_nil!.name.should contain("Nil")
    end
  end

  describe "block-dependent query return inference" do
    it "does not enqueue the bare alias after admitting an exact untyped-parameter target" do
      source = <<-CRYSTAL
        class LookupBox
          def find_entry(key)
            key
          end

          def fetch(key : String)
            find_entry(key)
          end
        end
      CRYSTAL

      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
      converter.arena = arena
      class_nodes = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode) }
      class_nodes.each { |node| converter.register_class(node) }

      converter.__test_lower_function_if_needed("LookupBox#fetch$String")

      fetch = converter.module.function_by_name("LookupBox#fetch$String")
      fetch.should_not be_nil
      find_entry_call = fetch.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call)
      end.find { |call| call.method_name.includes?("#find_entry") }
      find_entry_call.should_not be_nil
      find_entry_call.not_nil!.method_name.should eq("LookupBox#find_entry$String")
      converter.__test_pending_function?("LookupBox#find_entry$String").should be_true
      converter.__test_pending_function?("LookupBox#find_entry").should be_false
    end

    it "keeps block-return-dependent query calls typed from the block instead of Bool" do
      previous = ENV["ADAMAS_DISABLE_INLINE_YIELD"]?
      ENV["ADAMAS_DISABLE_INLINE_YIELD"] = "1"
      begin
        converter = lower_program_with_main(<<-CRYSTAL)
          class Worker
            def read_section?(name, &)
              return nil if name == "miss"

              if name == "hit"
                yield 1, 2
              end
            end

            def use
              read_section?("hit") { |sh, io| sh + io }
            end
          end

          Worker.new.use
        CRYSTAL

        use_func = converter.module.functions.find { |func| func.name.starts_with?("Worker#use") }
        use_func.should_not be_nil

        section_call = use_func.not_nil!.blocks.flat_map(&.instructions).find do |inst|
          inst.is_a?(Adamas::HIR::Call) && inst.as(Adamas::HIR::Call).method_name.starts_with?("Worker#read_section?")
        end
        section_call.should_not be_nil

        call_type = section_call.not_nil!.as(Adamas::HIR::Call).type
        type_name = converter.__test_get_type_name_from_ref(call_type)
        call_desc = converter.module.get_type_descriptor(call_type)
        call_desc.try(&.kind).should eq(Adamas::HIR::TypeKind::Union)
        type_name.should contain("Int32")
        type_name.should contain("Nil")
        type_name.should_not eq("Bool")
      ensure
        if previous
          ENV["ADAMAS_DISABLE_INLINE_YIELD"] = previous
        else
          ENV.delete("ADAMAS_DISABLE_INLINE_YIELD")
        end
      end
    end

    it "repairs stale direct call types from finalized callee returns" do
      previous = ENV["ADAMAS_DISABLE_INLINE_YIELD"]?
      ENV["ADAMAS_DISABLE_INLINE_YIELD"] = "1"
      begin
        converter = lower_program_with_sources(<<-CRYSTAL)
          class Worker
            def use
              read_section?("hit") { |sh, io| sh }
            end

            def read_section?(name, &)
              return nil if name == "miss"

              seek(1) do
                yield 1, 2
              end
            end

            def seek(pos, &)
              yield
            end
          end

          Worker.new.use
        CRYSTAL

        use_func = converter.module.functions.find { |func| func.name.starts_with?("Worker#use") }
        use_func.should_not be_nil

        section_index = use_func.not_nil!.blocks[0].instructions.index! do |inst|
          inst.is_a?(Adamas::HIR::Call) && inst.as(Adamas::HIR::Call).method_name.starts_with?("Worker#read_section?")
        end
        original_call = use_func.not_nil!.blocks[0].instructions[section_index].as(Adamas::HIR::Call)
        use_func.not_nil!.blocks[0].instructions[section_index] = Adamas::HIR::Call.new(
          original_call.id,
          Adamas::HIR::TypeRef::BOOL,
          original_call.receiver,
          original_call.method_name,
          original_call.args,
          original_call.block,
          original_call.virtual
        )

        converter.__test_repair_stale_call_return_types

        repaired_call = use_func.not_nil!.blocks[0].instructions[section_index].as(Adamas::HIR::Call)
        repaired_desc = converter.module.get_type_descriptor(repaired_call.type)
        repaired_desc.should_not be_nil
        repaired_desc.not_nil!.kind.should eq(Adamas::HIR::TypeKind::Union)
        repaired_desc.not_nil!.name.should contain("Nil")
        repaired_desc.not_nil!.name.should contain("Int32")
      ensure
        if previous
          ENV["ADAMAS_DISABLE_INLINE_YIELD"] = previous
        else
          ENV.delete("ADAMAS_DISABLE_INLINE_YIELD")
        end
      end
    end
  end

  describe "inline block tuple binding" do
    it "destructures yielded tuples for multi-param blocks without retargeting the first param to the whole tuple" do
      converter = lower_program_with_sources(<<-CRYSTAL)
        struct Point
          property val : Float64
          property ts : Int64

          def initialize(@val : Float64, @ts : Int64)
          end
        end

        def same_point?(expected : Point, actual : Point) : Bool
          expected.ts == actual.ts
        end

        def assert_points(expected : Array(Point), actual : Array(Point)) : Bool
          expected.zip(actual).all? { |e, a| same_point?(e, a) }
        end

        p1 = Point.new(1.0, 1_i64)
        p2 = Point.new(2.0, 2_i64)
        assert_points([p1], [p2])
      CRYSTAL

      func = converter.module.function_by_name("assert_points$Array(Point)_Array(Point)")
      func.should_not be_nil

      text = hir_text(func.not_nil!)
      text.should contain("call same_point?$Point_Point")
      text.should_not contain("same_point?$Tuple(Point, Point)_Point")
    end
  end

  describe "yield target transport" do
    it "marks the runtime block parameter and records it on HIR Yield" do
      previous = ENV["ADAMAS_DISABLE_INLINE_YIELD"]?
      ENV["ADAMAS_DISABLE_INLINE_YIELD"] = "1"
      begin
        converter = lower_program_with_sources(<<-CRYSTAL)
          class BlockOwner
            def predicate(&)
              yield true
            end
          end

          BlockOwner.new.predicate { |value| value }
        CRYSTAL

        func = converter.module.functions.find { |candidate| candidate.name.starts_with?("BlockOwner#predicate") }
        func.should_not be_nil
        block_param = func.not_nil!.params.find(&.is_block)
        block_param.should_not be_nil
        yielded = func.not_nil!.blocks
          .flat_map(&.instructions)
          .find(&.is_a?(Adamas::HIR::Yield))
          .not_nil!
          .as(Adamas::HIR::Yield)
        yielded.target.should eq(block_param.not_nil!.id)
      ensure
        if previous
          ENV["ADAMAS_DISABLE_INLINE_YIELD"] = previous
        else
          ENV.delete("ADAMAS_DISABLE_INLINE_YIELD")
        end
      end
    end
  end

  describe "Time.instant lowering" do
    it "registers Time.instant as a typed Time::Instant call instead of an unresolved void-like call" do
      converter = lower_program_with_sources(<<-CRYSTAL)
        class Time
          struct Instant
          end
        end

        def Time.instant : Time::Instant
          uninitialized Time::Instant
        end

        Time.instant()
      CRYSTAL

      converter.module.function_by_name("Time.instant$arity0").should_not be_nil

      main = converter.module.function_by_name("__adamas_main")
      main.should_not be_nil

      text = hir_text(main.not_nil!)
      text.should contain("call Time.instant()")
      text.should_not contain("call Time.instant() : 0")
    end

    it "keeps top-level path receivers on singleton defs during registration" do
      converter = lower_program_with_sources(<<-CRYSTAL)
        class Time
          class Location
          end
        end

        def Time::Location.utc : Int32
          1
        end

        Time::Location.utc()
      CRYSTAL

      converter.module.function_by_name("Time::Location.utc$arity0").should_not be_nil

      main = converter.module.function_by_name("__adamas_main")
      main.should_not be_nil

      text = hir_text(main.not_nil!)
      text.should contain("call Time::Location.utc()")
      text.should_not contain("call utc()")
    end

    it "keeps overloaded Time::Instant subtraction typed as Time::Span at call sites" do
      converter = lower_program_with_sources(<<-CRYSTAL)
        class Time
          struct Span
            def total_milliseconds : Int32
              1
            end
          end

          struct Instant
            def -(other : self) : Time::Span
              uninitialized Time::Span
            end
          end
        end

        def Time.instant : Time::Instant
          uninitialized Time::Instant
        end

        def probe : Int32
          started = Time.instant
          elapsed = Time.instant - started
          elapsed.total_milliseconds
        end

        probe()
      CRYSTAL

      converter.__test_get_function_return_type("Time::Instant#-$Time::Instant").should eq(
        converter.__test_type_ref_for_name("Time::Span")
      )

      probe = converter.module.functions.find do |func|
        func.name == "probe" || func.name.starts_with?("probe$")
      end
      probe.should_not be_nil

      text = hir_text(probe.not_nil!)
      text.should contain("Time::Span#total_milliseconds")
      text.should_not contain("Time::Instant#total_milliseconds")
    end
  end

  describe "unary wrapping negation lowering" do
    it "lowers unary &- as a real negation instead of a void-like method call" do
      converter = lower_program_with_sources(<<-CRYSTAL)
        def probe(x : UInt64) : UInt64
          &-x
        end

        probe(16_u64)
      CRYSTAL

      probe = converter.module.function_by_name("probe$UInt64")
      probe.should_not be_nil

      text = hir_text(probe.not_nil!)
      text.should contain("unop Neg")
      text.should_not contain("UInt64#&-() : 0")
    end
  end

  describe "Pointer#value boundaries" do
    it "does not substitute an ambient generic type into Pointer(Void)#value" do
      converter = lower_program_with_main(<<-CRYSTAL)
        class PointerValueBoundary(T)
          def read(pointer : Pointer(Void))
            pointer.value
          end
        end

        def boundary_read(box : PointerValueBoundary(Int32), pointer : Pointer(Void))
          box.read(pointer)
        end

        boundary_read(PointerValueBoundary(Int32).new, Pointer(Void).null)
      CRYSTAL

      read = converter.module.functions.find do |function|
        function.name.starts_with?("PointerValueBoundary(Int32)#read$Pointer(Void)")
      end
      read.should_not be_nil
      read.not_nil!.return_type.should eq(Adamas::HIR::TypeRef::VOID)
      loads = read.not_nil!.blocks.flat_map(&.instructions)
        .compact_map(&.as?(Adamas::HIR::PointerLoad))
      loads.size.should eq(1)
      loads.first.type.should eq(Adamas::HIR::TypeRef::VOID)
    end

    it "unwraps a sole concrete pointer arm before loading value" do
      converter = lower_program_with_main(<<-CRYSTAL)
        def load_optional(pointer : Pointer(Int32) | Nil) : Int32
          return 0 unless pointer
          pointer.value
        end

        load_optional(Pointer(Int32).null)
      CRYSTAL

      load = converter.module.functions.find do |function|
        function.name.starts_with?("load_optional$")
      end
      load.should_not be_nil
      instructions = load.not_nil!.blocks.flat_map(&.instructions)
      unwrap = instructions.compact_map(&.as?(Adamas::HIR::UnionUnwrap))
      pointer_load = instructions.compact_map(&.as?(Adamas::HIR::PointerLoad))
      unwrap.size.should eq(1)
      pointer_load.size.should eq(1)
      pointer_load.first.type.should eq(Adamas::HIR::TypeRef::INT32)
    end
  end

  describe "Pointer(Void) arithmetic" do
    it "keeps Pointer(Void) addition byte-strided inside struct initializers" do
      converter = lower_program_with_sources(<<-CRYSTAL)
        class StackBox
          def initialize(@pointer : Pointer(Void), @size : Int32)
            @bottom = @pointer + @size
          end
        end
      CRYSTAL

      init = converter.module.function_by_name("StackBox#initialize$Pointer(Void)_Int32")
      init.should_not be_nil

      pointer_add = init.not_nil!.blocks.flat_map(&.instructions).find(&.is_a?(Adamas::HIR::PointerAdd))
      pointer_add.should_not be_nil
      pointer_add.not_nil!.as(Adamas::HIR::PointerAdd).element_type.should eq(Adamas::HIR::TypeRef::UINT8)
    end
  end

  describe "accessor lowering" do
    it "materializes setter bodies even when the signature was pre-registered" do
      converter = lower_program_with_sources(<<-CRYSTAL)
        class Box
          property value : Int32

          def initialize
            @value = 0
          end
        end

        box = Box.new
        box.value = 10
      CRYSTAL

      setter = converter.module.function_by_name("Box#value=$Int32")
      setter.should_not be_nil
      setter.not_nil!.blocks.any? { |block| !block.instructions.empty? }.should be_true

      setter_text = hir_text(setter.not_nil!)
      setter_text.should contain("field_set")
      setter_text.should_not contain("unreachable")
    end
  end

  describe "nilable overload callsite selection" do
    it "selects Nil for a currently-nil Slice union and Slice for a concrete argument" do
      converter = lower_program_with_sources(<<-CRYSTAL)
        def choose(value : Nil) : Int32
          1
        end

        def choose(value : Slice(UInt8)) : Int32
          2
        end

        def choose(value : String) : Int32
          3
        end

        class ConstructorProbe
          def self.new(value : Nil) : Int32
            11
          end

          def self.new(value : Slice(UInt8)) : Int32
            12
          end
        end

        def nil_control : Int32
          value : Slice(UInt8)? = nil
          choose(value)
        end

        def slice_control(value : Slice(UInt8)) : Int32
          choose(value)
        end

        def three_variant_control(value : Nil | Slice(UInt8) | String) : Int32
          choose(value)
        end

        def constructor_control : Int32
          value : Slice(UInt8)? = nil
          ConstructorProbe.new(value)
        end
      CRYSTAL

      nil_control = converter.module.functions.find { |func| func.name.starts_with?("nil_control") }
      slice_control = converter.module.functions.find { |func| func.name.starts_with?("slice_control") }
      three_variant_control = converter.module.functions.find { |func| func.name.starts_with?("three_variant_control") }
      constructor_control = converter.module.functions.find { |func| func.name.starts_with?("constructor_control") }
      nil_control.should_not be_nil
      slice_control.should_not be_nil
      three_variant_control.should_not be_nil
      constructor_control.should_not be_nil

      nil_calls = nil_control.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call).try(&.method_name)
      end
      slice_calls = slice_control.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call).try(&.method_name)
      end

      # A nilable value is a runtime union, so HIR must retain both concrete
      # overload identities behind a discriminator branch. The Nil branch
      # carries a scalar Nil literal; the Slice branch unwraps the payload.
      nil_calls.should contain("choose$Nil")
      nil_calls.should contain("choose$Slice(UInt8)")
      nil_calls.should_not contain("choose$Nil | Slice(UInt8)")

      nil_instructions = nil_control.not_nil!.blocks.flat_map(&.instructions)
      nil_instructions.count { |instruction| instruction.is_a?(Adamas::HIR::UnionIs) }.should eq(1)
      nil_call = nil_instructions.compact_map(&.as?(Adamas::HIR::Call)).find { |call| call.method_name == "choose$Nil" }
      nil_call.should_not be_nil
      nil_arg = nil_call.not_nil!.args.first
      nil_literal = nil_instructions.find { |instruction| instruction.id == nil_arg }
      nil_literal.should be_a(Adamas::HIR::Literal)
      nil_literal.not_nil!.as(Adamas::HIR::Literal).type.should eq(Adamas::HIR::TypeRef::NIL)
      slice_call = nil_instructions.compact_map(&.as?(Adamas::HIR::Call)).find { |call| call.method_name == "choose$Slice(UInt8)" }
      slice_call.should_not be_nil
      slice_arg = slice_call.not_nil!.args.first
      nil_instructions.find { |instruction| instruction.id == slice_arg }.should be_a(Adamas::HIR::UnionUnwrap)
      slice_calls.should contain("choose$Slice(UInt8)")
      slice_calls.should_not contain("choose$Nil")

      three_calls = three_variant_control.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call).try(&.method_name)
      end
      three_calls.should_not contain("choose$Nil")
      three_calls.should contain("choose$Slice(UInt8)")
      three_calls.should contain("choose$String")

      constructor_calls = constructor_control.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call).try(&.method_name)
      end
      constructor_calls.should contain("ConstructorProbe.new$Nil")
      constructor_calls.should contain("ConstructorProbe.new$Slice(UInt8)")
    end

    it "materializes allocator overloads before nilable constructor dispatch" do
      converter = lower_program_with_sources(<<-CRYSTAL)
        class AllocatorProbe
          def initialize(value : Nil)
            @kind = 1
          end

          def initialize(value : Slice(UInt8))
            @kind = 2
          end
        end

        def construct(value : Slice(UInt8)?) : Int32
          AllocatorProbe.new(value)
          0
        end
      CRYSTAL

      caller = converter.module.functions.find { |func| func.name.starts_with?("construct") }
      caller.should_not be_nil

      calls = caller.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
        instruction.as?(Adamas::HIR::Call).try(&.method_name)
      end
      calls.should contain("AllocatorProbe.new$Nil")
      calls.should contain("AllocatorProbe.new$Slice(UInt8)")
      calls.should_not contain("AllocatorProbe.new$Nil | Slice(UInt8)")

      nil_allocator = converter.module.function_by_name("AllocatorProbe.new$Nil")
      slice_allocator = converter.module.function_by_name("AllocatorProbe.new$Slice(UInt8)")
      nil_allocator.should_not be_nil
      slice_allocator.should_not be_nil
      nil_allocator.not_nil!.blocks.any? { |block| !block.instructions.empty? }.should be_true
      slice_allocator.not_nil!.blocks.any? { |block| !block.instructions.empty? }.should be_true
      hir_text(nil_allocator.not_nil!).should contain("AllocatorProbe#initialize$Nil")
      hir_text(slice_allocator.not_nil!).should contain("AllocatorProbe#initialize$Slice(UInt8)")
    end
  end

  describe "materialized symbol ABI identity" do
    it "uses the full positional suffix type instead of a narrower callsite variant" do
      arena, exprs = parse(<<-CRYSTAL)
        class Left
        end

        class Right
        end

        def accept(value : Left | Right)
          value
        end
      CRYSTAL
      converter = Adamas::HIR::AstToHir.new(arena)
      converter.arena = arena
      def_node = exprs.compact_map { |expr_id| arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode) }.first

      converter.__test_merge_call_arg_type_names_from_suffix(
        def_node,
        ["Left"],
        ["Left | Right"],
      ).should eq(["Left | Right"])
    end

    it "preserves a concrete inherited value type through a restricted wrapper" do
      converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
        struct NumericDispatchBase
          def hash(hasher : NumericDispatchHasher) : Int32
            hasher.number(self)
          end
        end

        struct NumericDispatchLeaf < NumericDispatchBase
        end

        struct NumericDispatchOther < NumericDispatchBase
        end

        class NumericDispatchHasher
          def self.reduce(value : NumericDispatchLeaf) : Int32
            1
          end

          def self.reduce(value : NumericDispatchOther) : Int32
            2
          end

          def number(value : NumericDispatchBase) : Int32
            NumericDispatchHasher.reduce(value)
          end
        end

        NumericDispatchLeaf.new.hash(NumericDispatchHasher.new)
        NumericDispatchOther.new.hash(NumericDispatchHasher.new)
      CRYSTAL
      converter.flush_pending_functions

      ["NumericDispatchLeaf", "NumericDispatchOther"].each do |value_type|
        hash_function = converter.module.function_by_name(
          "#{value_type}#hash$NumericDispatchHasher"
        )
        hash_function.should_not be_nil
        self_param = hash_function.not_nil!.params.first
        converter.__test_get_type_name_from_ref(self_param.type).should eq(value_type)

        number_call = hash_function.not_nil!.blocks.flat_map(&.instructions)
          .compact_map(&.as?(Adamas::HIR::Call))
          .find { |call| call.method_name.includes?("#number") }
        number_call.should_not be_nil
        number_call.not_nil!.args.first.should eq(self_param.id)
        number_call.not_nil!.method_name.should eq(
          "NumericDispatchHasher#number$#{value_type}"
        )

        number_function = converter.module.function_by_name(number_call.not_nil!.method_name)
        number_function.should_not be_nil
        reduce_call = number_function.not_nil!.blocks.flat_map(&.instructions)
          .compact_map(&.as?(Adamas::HIR::Call))
          .find { |call| call.method_name.includes?(".reduce") }
        reduce_call.should_not be_nil
        reduce_call.not_nil!.method_name.should eq(
          "NumericDispatchHasher.reduce$#{value_type}"
        )
      end

      leaked_base_redispatches = converter.module.functions.flat_map(&.blocks)
        .flat_map(&.instructions)
        .compact_map(&.as?(Adamas::HIR::Call))
        .select do |call|
          call.method_name == "NumericDispatchHasher.reduce$NumericDispatchBase"
      end
      leaked_base_redispatches.should be_empty

      base_hash_name = "NumericDispatchBase#hash$NumericDispatchHasher"
      converter.module.functions.any? do |function|
        function.name.starts_with?("NumericDispatchBase#hash") &&
          converter.module.has_function_with_body?(function.name)
      end.should be_false

      # Replaying the inherited source definition for concrete value owners
      # must materialize only those concrete candidates. The source Def remains
      # semantic authority, but its parent-owned symbol is not an extra runtime
      # target unless a parent-typed call explicitly demands it.
      converter.__test_record_virtual_target(
        "NumericDispatchBase",
        "hash",
        [converter.__test_type_ref_for_name("NumericDispatchHasher")],
      )
      converter.__test_replay_virtual_targets_for_registered_class("NumericDispatchLeaf")
      converter.__test_replay_virtual_targets_for_registered_class("NumericDispatchOther")
      converter.module.functions.any? do |function|
        function.name.starts_with?("NumericDispatchBase#hash") &&
          converter.module.has_function_with_body?(function.name)
      end.should be_false

      # Deferral must not ban a real parent-typed demand. The registered source
      # template remains available and is materialized only when requested.
      converter.__test_lower_function_if_needed(base_hash_name)
      base_hash = converter.module.function_by_name(base_hash_name)
      base_hash.should_not be_nil
      base_number_call = base_hash.not_nil!.blocks.flat_map(&.instructions)
        .compact_map(&.as?(Adamas::HIR::Call))
        .find { |call| call.method_name.includes?("#number") }
      base_number_call.should_not be_nil
      base_number_call.not_nil!.method_name.should eq(
        "NumericDispatchHasher#number$NumericDispatchBase"
      )
    end

    it "specializes a broad value-union wrapper at the concrete call site" do
      converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
        class Object
        end

        class ValueUnionSink < Object
          def append(value : Char | Number | String) : Nil
            value.render(self)
          end
        end

        struct Number
          abstract def render(io : ValueUnionSink) : Nil
        end

        struct Int
        end

        struct Int32
          def render(io : ValueUnionSink) : Nil
          end
        end

        abstract struct AbstractNumberLeaf < Number
          abstract def render(io : ValueUnionSink) : Nil
        end

        struct Char
          def render(io : ValueUnionSink) : Nil
          end
        end

        class String < Object
          def render(io : ValueUnionSink) : Nil
          end
        end

        ValueUnionSink.new.append(1)
        ValueUnionSink.new.append("value")
      CRYSTAL
      converter.flush_pending_functions

      {
        "Int32" => Adamas::HIR::TypeRef::INT32,
        "String" => Adamas::HIR::TypeRef::STRING,
      }.each do |value_type, type_ref|
        wrapper = converter.module.function_by_name("ValueUnionSink#append$#{value_type}")
        wrapper.should_not be_nil
        wrapper.not_nil!.params[1].type.should eq(type_ref)

        render_calls = wrapper.not_nil!.blocks.flat_map(&.instructions)
          .compact_map(&.as?(Adamas::HIR::Call))
          .select { |call| call.method_name.includes?("#render") }
        render_calls.map(&.method_name).should eq(["#{value_type}#render$ValueUnionSink"])
      end

      converter.module.has_function_with_body?(
        "ValueUnionSink#append$Char | Number | String"
      ).should be_false
      converter.module.has_function_with_body?("Number#render$ValueUnionSink").should be_false

      runtime_union = converter.__test_type_ref_for_name("Char | Number | String")
      converter.__test_get_type_name_from_ref(runtime_union).should eq(
        "Char | Int32 | String"
      )
      descriptor = converter.union_descriptors[Adamas::MIR::TypeRef.from_hir(runtime_union)]
      descriptor.variants.map(&.full_name).should eq(["Char", "Int32", "String"])
    end

    it "keeps abstract reference arms header-backed in runtime unions" do
      converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
        class Object
        end

        class RuntimeUnionReferenceBase < Object
        end

        class RuntimeUnionReferenceLeaf < RuntimeUnionReferenceBase
        end

        struct Int32
        end
      CRYSTAL

      runtime_union = converter.__test_type_ref_for_name(
        "Int32 | RuntimeUnionReferenceBase"
      )
      converter.__test_get_type_name_from_ref(runtime_union).should eq(
        "Int32 | RuntimeUnionReferenceBase"
      )
      descriptor = converter.union_descriptors[Adamas::MIR::TypeRef.from_hir(runtime_union)]
      descriptor.variants.map(&.full_name).should eq(["Int32", "RuntimeUnionReferenceBase"])
    end

    it "keeps concrete value arms intact in runtime unions" do
      converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
        struct ConcreteValueBase
        end

        struct ConcreteValueLeaf < ConcreteValueBase
        end

        struct Int32
        end
      CRYSTAL

      runtime_union = converter.__test_type_ref_for_name(
        "ConcreteValueBase | Int32"
      )
      converter.__test_get_type_name_from_ref(runtime_union).should eq(
        "ConcreteValueBase | Int32"
      )
      descriptor = converter.union_descriptors[Adamas::MIR::TypeRef.from_hir(runtime_union)]
      descriptor.variants.map(&.full_name).should eq(["ConcreteValueBase", "Int32"])
    end

    it "does not recurse into nested union annotations during specialization" do
      converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
        class Object
        end

        struct Box(T)
        end

        struct Int32
        end

        class String < Object
        end

        class NestedUnionSink < Object
          def accept(value : Box(Int32 | String)) : Nil
          end
        end

        NestedUnionSink.new.accept(Box(Int32 | String).new)
      CRYSTAL
      converter.flush_pending_functions

      converter.module.has_function_with_body?(
        "NestedUnionSink#accept$Box(Int32 | String)"
      ).should be_true
    end

    it "refreshes cached numeric unions after late descendant registration" do
      source = <<-CRYSTAL
        struct Number
        end

        struct Int32 < Number
        end

        class String
        end
      CRYSTAL
      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena
      class_nodes = exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
      end

      converter.register_class(class_nodes[0])
      converter.register_class(class_nodes[2])
      converter.__test_get_type_name_from_ref(
        converter.__test_type_ref_for_name("Number | String")
      ).should eq("Number | String")
      cached_annotation = converter.__test_annotation_type_ref("Number | String")
      converter.__test_type_ref_for_name("Number___String")
      converter.__test_annotation_type_ref("(Number | String)")

      converter.register_class(class_nodes[1])

      converter.__test_subclasses("Number").should contain("Int32")
      converter.__test_cached_union_type_ref_stale(
        cached_annotation,
        "Number | String",
      ).should be_true

      {
        converter.__test_type_ref_for_name("Number|String"),
        converter.__test_type_ref_for_name("Number___String"),
        converter.__test_type_ref_for_name("Number | String"),
        converter.__test_annotation_type_ref("Number | String"),
        converter.__test_annotation_type_ref("(Number | String)"),
      }.each do |runtime_union|
        converter.__test_get_type_name_from_ref(runtime_union).should eq("Int32 | String")
        descriptor = converter.union_descriptors[Adamas::MIR::TypeRef.from_hir(runtime_union)]
        descriptor.variants.map(&.full_name).should eq(["Int32", "String"])
      end
    end
  end

  describe "NoReturn call demand" do
    it "does not materialize a call whose argument is proven NoReturn" do
      converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
        struct NoReturnArgumentProbe
          def accept(value : Int32, later : Int32)
            value + later
          end
        end

        def no_return_argument_stop : NoReturn
          raise "stop"
        end

        def no_return_argument_receiver
          NoReturnArgumentProbe.new
        end

        def no_return_argument_after
          1
        end

        def no_return_argument_later
          2
        end

        def no_return_argument_run
          no_return_argument_receiver.accept(no_return_argument_stop, no_return_argument_later)
          no_return_argument_after
        end

        no_return_argument_run
      CRYSTAL

      run = converter.module.function_by_name("no_return_argument_run")
      run.should_not be_nil
      run_calls = run.not_nil!.blocks.flat_map(&.instructions)
        .compact_map(&.as?(Adamas::HIR::Call))
      accept_calls = run_calls.select { |call| call.method_name.includes?("#accept") }

      run_calls.any? { |call| call.method_name == "no_return_argument_receiver" }.should be_true
      run_calls.any? { |call| call.method_name == "no_return_argument_stop" }.should be_true
      accept_calls.should be_empty
      run_calls.any? { |call| call.method_name == "no_return_argument_later" }.should be_false
      run_calls.any? { |call| call.method_name == "no_return_argument_after" }.should be_false
      converter.module.functions.any? do |function|
        function.name.starts_with?("NoReturnArgumentProbe#accept$NoReturn")
      end.should be_false
    end

    it "stops before an operator after assigning a NoReturn call" do
      converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
        struct NoReturnOffsetProbe(T)
          def +(offset : Int32)
            self
          end
        end

        def no_return_offset_stop : NoReturn
          raise "stop"
        end

        def no_return_offset_after
          1
        end

        def no_return_offset_run
          value = NoReturnOffsetProbe(Int32).new
          offset = no_return_offset_stop
          value += offset
          no_return_offset_after
        end

        no_return_offset_run
      CRYSTAL

      run = converter.module.function_by_name("no_return_offset_run")
      run.should_not be_nil
      run_calls = run.not_nil!.blocks.flat_map(&.instructions)
        .compact_map(&.as?(Adamas::HIR::Call))

      run_calls.any? { |call| call.method_name == "no_return_offset_stop" }.should be_true
      run_calls.any? { |call| call.method_name.includes?("NoReturnOffsetProbe(Int32)#+") }.should be_false
      run_calls.any? { |call| call.method_name == "no_return_offset_after" }.should be_false
      converter.module.functions.any? do |function|
        function.name.starts_with?("NoReturnOffsetProbe(Int32)#+$NoReturn")
      end.should be_false
    end

    it "does not treat a live overload as NoReturn from a sibling annotation" do
      converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
        def no_return_overloaded(value : Int32) : NoReturn
          raise "stop"
        end

        def no_return_overloaded(value : String)
          7
        end

        def no_return_overload_sink(value : Int32)
          value
        end

        def no_return_overload_after
          1
        end

        def no_return_overload_run
          no_return_overload_sink(no_return_overloaded("ok"))
          no_return_overload_after
        end

        no_return_overload_run
      CRYSTAL

      run = converter.module.function_by_name("no_return_overload_run")
      run.should_not be_nil
      run_calls = run.not_nil!.blocks.flat_map(&.instructions)
        .compact_map(&.as?(Adamas::HIR::Call))

      run_calls.any? { |call| call.method_name == "no_return_overloaded$String" }.should be_true
      run_calls.any? { |call| call.method_name == "no_return_overload_sink$Int32" }.should be_true
      run_calls.any? { |call| call.method_name == "no_return_overload_after" }.should be_true
    end

    it "does not terminate a virtual call from the base NoReturn annotation" do
      converter = lower_program_with_main(<<-CRYSTAL, source_backed: true)
        class NoReturnVirtualBase
          def probe(value : Int32) : NoReturn
            raise "base stop"
          end
        end

        class NoReturnVirtualFlow < NoReturnVirtualBase
          def probe(value : Int32)
            value
          end
        end

        def no_return_virtual_after
          1
        end

        def no_return_virtual_run(base : NoReturnVirtualBase)
          base.probe(1)
          no_return_virtual_after
        end

        no_return_virtual_run(NoReturnVirtualFlow.new)
      CRYSTAL

      run = converter.module.function_by_name("no_return_virtual_run$NoReturnVirtualBase")
      run.should_not be_nil
      run_calls = run.not_nil!.blocks.flat_map(&.instructions)
        .compact_map(&.as?(Adamas::HIR::Call))

      probe = run_calls.find { |call| call.method_name.includes?("#probe") }
      probe.should_not be_nil
      probe.not_nil!.virtual.should be_true
      run_calls.any? { |call| call.method_name == "no_return_virtual_after" }.should be_true
    end
  end

  describe "abstract binary operator dispatch" do
    it "does not borrow a typed equality overload from a sibling callsite" do
      source = <<-CRYSTAL
        class EqualityBox
          def ==(other : EqualityBox)
            true
          end
        end
      CRYSTAL
      arena, exprs = parse(source)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => source},
      )
      converter.arena = arena
      class_node = exprs.compact_map do |expr_id|
        arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
      end.first
      converter.register_class(class_node)

      box_ref = converter.__test_type_ref_for_name("EqualityBox")
      compatible_name = "EqualityBox#==$EqualityBox"
      incompatible_name = "EqualityBox#==$Int32"
      converter.__test_remember_callsite_arg_types(compatible_name, [box_ref])
      converter.__test_remember_callsite_arg_types(incompatible_name, [Adamas::HIR::TypeRef::INT32])

      converter.__test_lower_function_if_needed(incompatible_name)
      converter.module.has_function_with_body?(compatible_name).should be_false
      converter.module.has_function_with_body?(incompatible_name).should be_false

      converter.__test_lower_function_if_needed(compatible_name)
      converter.module.has_function_with_body?(compatible_name).should be_true
    end

    it "uses only complete positional suffixes as authoritative evidence" do
      arena, _ = parse("")
      converter = Adamas::HIR::AstToHir.new(arena)

      converter.__test_concrete_suffix_types_for_reselect?("Int32", 1).should be_true
      converter.__test_concrete_suffix_types_for_reselect?("Int32_String", 2).should be_true
      converter.__test_concrete_suffix_types_for_reselect?("Int32", nil).should be_false
      converter.__test_concrete_suffix_types_for_reselect?("Int32_block", 1).should be_false
      converter.__test_concrete_suffix_types_for_reselect?("Int32$arity2", 2).should be_false
      converter.__test_concrete_suffix_types_for_reselect?("arity2", 2).should be_false
      converter.__test_concrete_suffix_types_for_reselect?("Int32_arity2", 2).should be_false
      converter.__test_concrete_suffix_types_for_reselect?("My_Type", 1).should be_false
    end

    it "keeps the operator call virtual and materializes the concrete override" do
      converter = lower_program_with_sources(<<-CRYSTAL)
        abstract class EqualityRoot
          abstract def ==(other)

          def matches(other)
            self == other
          end
        end

        class EqualityLeaf < EqualityRoot
          def ==(other)
            true
          end
        end

        def compare(root : EqualityRoot, value : Int32)
          root.matches(value)
        end
      CRYSTAL

      converter.__test_lower_function_if_needed("EqualityRoot#matches$Int32")
      converter.__test_process_pending_lower_functions
      matches = converter.module.function_by_name("EqualityRoot#matches$Int32")
      matches.should_not be_nil
      equality_call = matches.not_nil!.blocks.flat_map(&.instructions)
        .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
        .find { |call| call.method_name.includes?("#==") }
      equality_call.should_not be_nil
      equality_call.not_nil!.virtual.should be_true

      leaf_target = converter.module.functions.find do |function|
        function.name.starts_with?("EqualityLeaf#==$Int32")
      end
      leaf_target.should_not be_nil
      leaf_target.not_nil!.blocks.any? { |block| !block.instructions.empty? }.should be_true
    end
  end
end
