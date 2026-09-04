# Debug hooks for HIR compiler - zero overhead when disabled
#
# Usage:
#   1. Build with: crystal build -Ddebug_hooks src/main.cr
#   2. Set hooks before compilation:
#
#      DebugHooks.on_type_resolve = ->(name : String, context : String, result : String) {
#        STDERR.puts "#{name} in #{context} -> #{result}" if name.includes?("Seek")
#      }
#
#   3. Run compiler - hooks will be called at key points
#
# Available hooks:
#   - on_type_resolve(name, context, result) - when a type name is resolved
#   - on_method_register(full_name, class_name, method_name) - when a method is registered
#   - on_class_register(class_name, parent) - when a class/struct is registered
#   - on_enum_register(enum_name, base_type) - when an enum is registered

module DebugHooks
  # Compile-time flag for zero overhead
  ENABLED = {{ flag?(:debug_hooks) }}

  {% if flag?(:debug_hooks) %}
    @@on_type_resolve : Proc(String, String, String, Nil)?
    @@on_method_register : Proc(String, String, String, Nil)?
    @@on_class_register : Proc(String, String?, Nil)?
    @@on_enum_register : Proc(String, String, Nil)?
    @@on_debug : Proc(String, String, Nil)?

    class_property on_type_resolve : Proc(String, String, String, Nil)?
    class_property on_method_register : Proc(String, String, String, Nil)?
    class_property on_class_register : Proc(String, String?, Nil)?
    class_property on_enum_register : Proc(String, String, Nil)?
    class_property on_debug : Proc(String, String, Nil)?

    def self.type_resolve(name : String, context : String, result : String)
      @@on_type_resolve.try &.call(name, context, result)
    end

    def self.method_register(full_name : String, class_name : String, method_name : String)
      @@on_method_register.try &.call(full_name, class_name, method_name)
    end

    def self.class_register(class_name : String, parent : String?)
      @@on_class_register.try &.call(class_name, parent)
    end

    def self.enum_register(enum_name : String, base_type : String)
      @@on_enum_register.try &.call(enum_name, base_type)
    end

    def self.debug(event : String, data : String)
      @@on_debug.try &.call(event, data)
    end
  {% else %}
    # No-op stubs - LLVM will optimize these away completely
    def self.type_resolve(name : String, context : String, result : String)
    end

    def self.method_register(full_name : String, class_name : String, method_name : String)
    end

    def self.class_register(class_name : String, parent : String?)
    end

    def self.enum_register(enum_name : String, base_type : String)
    end

    def self.debug(event : String, data : String)
    end
  {% end %}
end

# Macros for convenient hook calls - expands to method call or nothing
macro debug_hook_type_resolve(name, context, result)
  {% if flag?(:debug_hooks) %}
    DebugHooks.type_resolve({{name}}, {{context}}, {{result}})
  {% end %}
end

macro debug_hook_method_register(full_name, class_name, method_name)
  {% if flag?(:debug_hooks) %}
    DebugHooks.method_register({{full_name}}, {{class_name}}, {{method_name}})
  {% end %}
end

macro debug_hook_class_register(class_name, parent)
  {% if flag?(:debug_hooks) %}
    DebugHooks.class_register({{class_name}}, {{parent}})
  {% end %}
end

macro debug_hook_enum_register(enum_name, base_type)
  {% if flag?(:debug_hooks) %}
    DebugHooks.enum_register({{enum_name}}, {{base_type}})
  {% end %}
end

macro debug_hook(event, data)
  {% if flag?(:debug_hooks) %}
    DebugHooks.debug({{event}}, {{data}})
  {% end %}
end

# Keep the legacy lower-call arena ledgers out of ordinary compiler builds.
# The runtime environment variables remain the fine-grained switch for builds
# compiled with -Ddebug_hooks.
macro debug_lower_call_arena_phase(ctx, node, label, call_arena = nil)
  {% if flag?(:debug_hooks) %}
    trace_lower_call_arena_phase({{ctx}}, {{node}}, {{label}}, {{call_arena}})
  {% end %}
end

macro debug_lower_call_arena_expr(ctx, node, label, expr_id, arena_owner, origin)
  {% if flag?(:debug_hooks) %}
    trace_lower_call_arena_expr(
      {{ctx}},
      {{node}},
      {{label}},
      {{expr_id}},
      {{arena_owner}},
      {{origin}},
    )
  {% end %}
end

# Keep legacy lower_call diagnostics out of ordinary compiler builds without
# placing macro control nodes inside the already-large lower_call body.
macro debug_lower_call_entry_diagnostics(ctx, node)
  {% if flag?(:debug_hooks) %}
    if env_get("DEBUG_MISSING_SYMS")
      callee_node_dbg = @arena[{{node}}.callee]
      method_name_dbg2 = case callee_node_dbg
                         when Adamas::Compiler::Frontend::MemberAccessNode
                           (safe_slice_to_string(callee_node_dbg.member) || "")
                         when Adamas::Compiler::Frontend::IdentifierNode
                           (safe_slice_to_string(callee_node_dbg.name) || "")
                         else
                           nil
                         end
      if method_name_dbg2 == "leap_year?" || method_name_dbg2 == "month_week_date"
        obj_dbg = case callee_node_dbg
                  when Adamas::Compiler::Frontend::MemberAccessNode
                    obj_node_dbg = @arena[callee_node_dbg.object]
                    "#{obj_node_dbg.class.name}(#{obj_node_dbg.is_a?(Adamas::Compiler::Frontend::ConstantNode) ? (safe_slice_to_string(obj_node_dbg.name) || "") : "?"})"
                  else
                    "bare"
                  end
        STDERR.puts "[LOWER_CALL_ENTRY_DBG] method=#{method_name_dbg2} obj=#{obj_dbg} func=#{ {{ctx}}.function.name } current_class=#{@current_class}"
      end
    end
    if env_get("DEBUG_UNION_CONV_ALL")
      callee_node = @arena[{{node}}.callee]
      method_name_dbg = case callee_node
                        when Adamas::Compiler::Frontend::MemberAccessNode
                          (safe_slice_to_string(callee_node.member) || "")
                        when Adamas::Compiler::Frontend::IdentifierNode
                          (safe_slice_to_string(callee_node.name) || "")
                        else
                          nil
                        end
      if method_name_dbg && (method_name_dbg == "to_i32!" || method_name_dbg == "to_u32!" || method_name_dbg == "to_u64!")
        STDERR.puts "[LOWER_CALL_ENTRY] method=#{method_name_dbg} func=#{ {{ctx}}.function.name }"
      end
    end
    if env_get("DEBUG_ENUM_UNION_PREDICATE")
      callee_node = @arena[{{node}}.callee]
      callee_name = case callee_node
                    when Adamas::Compiler::Frontend::MemberAccessNode
                      (safe_slice_to_string(callee_node.member) || "")
                    else
                      nil
                    end
      if callee_name && (callee_name == "kill?" || callee_name == "hup?" || callee_name == "quit?")
        STDERR.puts "[LOWER_CALL_SIGNAL] method=#{callee_name} func=#{ {{ctx}}.function.name }"
      end
    end
    if env_get("DEBUG_ALL_CALLS") || env_get("DEBUG_LOWER_CALL")
      callee_node = @arena[{{node}}.callee]
      callee_name = case callee_node
                    when Adamas::Compiler::Frontend::IdentifierNode
                      (safe_slice_to_string(callee_node.name) || "")
                    when Adamas::Compiler::Frontend::MemberAccessNode
                      (safe_slice_to_string(callee_node.member) || "")
                    else
                      "(other)"
                    end
      if env_get("DEBUG_ALL_CALLS") || callee_name == "byte_range"
        STDERR.puts "[LOWER_CALL] method=#{callee_name} callee_type=#{callee_node.class.name.split("::").last} current_class=#{@current_class || "nil"} block=#{ {{node}}.block.nil? ? "no" : "yes"} func=#{ {{ctx}}.function.name }"
      end
    end
    if env_get("DEBUG_INLINE_CRASH")
      if @inline_yield_name_stack.any? { |name| name.includes?("Char::Reader#decode_char_at") }
        stack = @inline_yield_name_stack.join(" -> ")
        if {{ctx}}.current_block >= {{ctx}}.function.blocks.size
          STDERR.puts "[INLINE_CRASH] block_oob call block=#{ {{ctx}}.current_block } size=#{ {{ctx}}.function.blocks.size } stack=#{stack}"
        end
        if source = source_for_arena(@arena)
          span = {{node}}.span
          start = span.start_offset
          length = span.end_offset - span.start_offset
          if length > 0 && start >= 0 && start < source.bytesize
            slice_len = length > 80 ? 80 : length
            snippet = source.byte_slice(start, slice_len).gsub(/\s+/, " ").strip
            STDERR.puts "[INLINE_CRASH] lower_call span=#{start}..#{span.end_offset} stack=#{stack} \"#{snippet}\""
          else
            STDERR.puts "[INLINE_CRASH] lower_call span=#{start}..#{span.end_offset} stack=#{stack}"
          end
        else
          STDERR.puts "[INLINE_CRASH] lower_call span=#{ {{node}}.span.start_offset }..#{ {{node}}.span.end_offset } stack=#{stack}"
        end
      end
    end
  {% end %}
end

macro debug_lower_call_member_entry(ctx, callee_node, obj_expr, obj_node, method_name)
  {% if flag?(:debug_hooks) %}
    if debug_env_filter_match?("DEBUG_TPM_CALL", {{method_name}})
      STDERR.puts "[TPM_CALL] method=#{ {{method_name}} } current=#{@current_class || "nil"} map=#{type_param_map_debug_string}"
    end
    if env_get("DEBUG_EXE_PATH_CALL") && {{method_name}} == "executable_path"
      raw_obj = stringify_type_expr({{obj_expr}}) || "(unknown)"
      obj_label = {{obj_node}}.class.name.split("::").last
      current_label = @current_class || "nil"
      override_label = @current_namespace_override || "nil"
      STDERR.puts "[DEBUG_EXE_PATH_CALL] early obj=#{obj_label} raw=#{raw_obj} current=#{current_label} override=#{override_label}"
    end
    if env_get("DEBUG_ENUM_PREDICATE") && {{method_name}} == "character_device?"
      STDERR.puts "[DEBUG_ENUM_CALL_PATH] lower_call method=#{ {{method_name}} } callee=#{ {{callee_node}}.class.name }"
    end
    if env_get("DEBUG_BYTEFORMAT_FORMAT") && {{method_name}} == "decode" &&
       {{obj_node}}.is_a?(Adamas::Compiler::Frontend::IdentifierNode) &&
       (safe_slice_to_string({{obj_node}}.name) || "") == "format"
      local_id = {{ctx}}.lookup_local("format")
      lit_flag = local_id ? {{ctx}}.type_literal?(local_id) : false
      local_type = local_id ? get_type_name_from_ref({{ctx}}.type_of(local_id)) : "nil"
      module_flag = local_id ? module_type_ref?({{ctx}}.type_of(local_id)) : false
      STDERR.puts "[BYTEFORMAT_FORMAT] lookup=#{local_id || "nil"} type=#{local_type} lit=#{lit_flag} module=#{module_flag} current=#{@current_class || "nil"}##{@current_method || "nil"} class_method=#{@current_method_is_class ? 1 : 0}"
    end
    if env_get("DEBUG_THREAD_RESOLVE") && {{method_name}} == "threads"
      STDERR.puts "[THREAD_RESOLVE_CALL] obj_node=#{ {{obj_node}}.class.name } current=#{@current_class || "nil"} override=#{@current_namespace_override || "nil"}"
    end
    if env_get("DEBUG_POINTER_LIST") && {{method_name}} == "new"
      if obj_name = stringify_type_expr({{obj_expr}})
        if obj_name.includes?("PointerLinkedList")
          STDERR.puts "[POINTER_LIST_AST] obj=#{obj_name} method=#{ {{method_name}} }"
        end
      end
    end
  {% end %}
end

macro debug_lower_call_read_attr(ctx, node, callee_node)
  {% if flag?(:debug_hooks) %}
    if env_get("DEBUG_READ_ATTR_CALL")
      callee_name = case {{callee_node}}
                    when Adamas::Compiler::Frontend::IdentifierNode
                      (safe_slice_to_string({{callee_node}}.name) || "")
                    when Adamas::Compiler::Frontend::MemberAccessNode
                      (safe_slice_to_string({{callee_node}}.member) || "")
                    else
                      nil
                    end
      if callee_name == "read_attribute_value"
        snippet = nil
        if source = source_for_arena(@arena)
          span = {{node}}.span
          start = span.start_offset
          length = span.end_offset - span.start_offset
          if length > 0 && start >= 0 && start < source.bytesize
            slice_len = length > 120 ? 120 : length
            snippet = source.byte_slice(start, slice_len).gsub(/\s+/, " ").strip
          end
        end
        snippet_label = snippet ? " \"#{snippet}\"" : ""
        STDERR.puts "[DEBUG_READ_ATTR_CALL] func=#{ {{ctx}}.function.name } class=#{@current_class || "nil"} arena=#{@arena.class}:#{@arena.size}#{snippet_label}"
      end
    end
  {% end %}
end

macro debug_hook_type_cache(name, context, cache_key, resolved_name)
  {% if flag?(:debug_hooks) %}
    DebugHooks.debug(
      "type_cache",
      "name=#{ {{name}} } context=#{ {{context}} } key=#{ {{cache_key}} } resolved=#{ {{resolved_name}} }"
    )
  {% end %}
end
