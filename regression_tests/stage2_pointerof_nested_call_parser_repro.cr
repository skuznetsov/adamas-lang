module Crystal::HIR
  class Stage2PointerofNestedCallParserRepro
    private def register_module_instance_methods_for(
      class_name : String,
      include_node : CrystalV2::Compiler::Frontend::IncludeNode,
      defined_full_names : Set(String),
      defined_class_method_full_names : Set(String),
      visited : Set(String),
      visited_extends : Set(String),
      ivars : Array(IVarInfo),
      offset : Int32,
      is_struct : Bool,
      init_capture : InitParamsCapture?,
    ) : Int32
      class_name = sanitize_type_name(class_name)
      module_full_name = resolve_path_like_name(include_node.target)
      return offset unless module_full_name

      if !module_full_name.includes?("::")
        base_owner = strip_generic_args(class_name)
        nested_name = "#{base_owner}::#{module_full_name}"
        module_full_name = nested_name if @module_defs.has_key?(nested_name)
      end

      unless @module_defs.has_key?(module_full_name)
        if class_name.includes?("::")
          if qualified_name = resolve_module_name_in_owner_namespaces(class_name, module_full_name)
            module_full_name = qualified_name
          end
        end
      end

      module_full_name = resolve_module_alias_for_include(module_full_name)
      record_module_inclusion(module_full_name, class_name, already_resolved: true)
      return offset if visited.includes?(module_full_name)
      visited << module_full_name

      defs = @module_defs[module_full_name]?
      return offset unless defs
      include_arena = @arena
      included_macro_lookup = lookup_macro_entry("included", module_full_name)
      include_param_map_cache = {} of String => Hash(String, String)
      defs.each do |mod_node, mod_arena|
        with_arena(mod_arena) do
          param_sig = module_type_params_signature(mod_node)
          extra_map = if cached = include_param_map_cache[param_sig]?
                        cached
                      else
                        computed = include_type_param_map(mod_node, include_node.target, include_arena, class_name)
                        include_param_map_cache[param_sig] = computed
                        computed
                      end
          with_type_param_map(extra_map) do
            if macro_lookup = included_macro_lookup
              macro_entry, macro_key = macro_lookup
              macro_def, macro_arena = macro_entry
              expanded_id = expand_macro_expr(macro_def, macro_arena, [] of ExprId, nil, nil, macro_key)
              old_arena = @arena
              @arena = macro_arena
              begin
                macro_body = macro_arena[macro_def.body]
                if macro_body.is_a?(CrystalV2::Compiler::Frontend::MacroLiteralNode)
                  if raw_text = macro_literal_raw_text(macro_body)
                    expanded = expand_flag_macro_text(raw_text) || raw_text
                    if parsed = parse_macro_literal_class_body(expanded)
                      parsed_arena, body_ids = parsed
                      with_arena(parsed_arena) do
                        body_ids.each do |child_id|
                          register_class_members_from_expansion(
                            class_name,
                            child_id,
                            defined_class_method_full_names,
                            visited_extends,
                            ivars,
                            pointerof(offset)
                          )
                        end
                      end
                    end
                  end
                end

                unless expanded_id.invalid?
                  register_class_members_from_expansion(
                    class_name,
                    expanded_id,
                    defined_class_method_full_names,
                    visited_extends,
                    ivars,
                    pointerof(offset)
                  )
                end
              ensure
                @arena = old_arena
              end
            end
          end
        end
      end

      offset
    end
  end
end
