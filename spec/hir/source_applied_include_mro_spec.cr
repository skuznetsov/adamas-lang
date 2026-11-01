require "../spec_helper"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_unknown_call_arg_types(arg_types : Array(TypeRef)?) : Bool?
    unknown_call_arg_types?(arg_types)
  end

  def __test_ivar_layout(owner : String)
    @class_info[owner].ivars.map { |ivar| {ivar.name, ivar.offset} }
  end

  def __test_mro_included_origin(owner : String, method_name : String, respect_direct_declarations : Bool = false)
    type_ref_for_name(owner)
    find_included_module_def_origin_for_owner(
      owner,
      method_name,
      0,
      true,
      respect_direct_declarations: respect_direct_declarations,
      compatible_arg_types: [] of TypeRef,
    )
  end

  def __test_source_direct_class_includes(owner : String)
    source_direct_class_includes(owner)
  end

  def __test_noarg_mro_included_origin(owner : String, method_name : String, materialize_owner : Bool = true)
    type_ref_for_name(owner) if materialize_owner
    find_included_module_def_origin_for_owner(
      owner,
      method_name,
      0,
      false,
      respect_direct_declarations: true,
      compatible_arg_types: [] of TypeRef,
    )
  end

  def __test_noarg_source_call_return(owner : String, method_name : String, receiver_type : TypeRef)
    included_module_call_return_type(
      owner,
      method_name,
      [] of ExprId,
      [] of TypeRef,
      nil,
      receiver_type,
    )
  end

  def __test_type_ref(name : String)
    type_ref_for_name(name)
  end

  def __test_emitted_noarg_application_calls(source_def : Adamas::Compiler::Frontend::DefNode,
                                             source_arena : Adamas::Compiler::Frontend::ArenaLike,
                                             source_method : String = "selected_value")
    main = @module.function_by_name("__adamas_main") || raise "missing lowered main"
    calls = main.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
      .select { |call| call.method_name.includes?("##{source_method}") }
    calls.map do |call|
      name = call.method_name
      registered_def = @function_defs[name]?
      registered_arena = @function_def_arenas[name]?
      {
        get_type_name_from_ref(call.type),
        function_namespace_override_for(name) || "",
        function_type_param_map_for_name(name).try { |map| map["T"]? } || "",
        registered_def.try { |definition| definition.same?(source_def) } || false,
        registered_arena.try { |arena| arena.object_id == source_arena.object_id } || false,
      }
    end
  end

  def __test_emitted_noarg_consumer_calls(consumer_method : String = "consume")
    main = @module.function_by_name("__adamas_main") || raise "missing lowered main"
    instructions = main.blocks.flat_map(&.instructions)
    values = {} of UInt32 => Adamas::HIR::Value
    instructions.each { |instruction| values[instruction.id] = instruction }
    instructions.compact_map(&.as?(Adamas::HIR::Call))
      .select { |call| parse_method_name_compact(call.method_name).method == consumer_method }
      .map do |call|
        argument = values[call.args.first]
        source_value = argument
        while cast = source_value.as?(Adamas::HIR::Cast)
          source_value = values[cast.value]
        end
        source_call = source_value.as?(Adamas::HIR::Call)
        {
          call.method_name,
          get_type_name_from_ref(call.type),
          get_type_name_from_ref(argument.type),
          source_call.try { |value| get_type_name_from_ref(value.type) } || "",
          source_call.try(&.method_name) || "",
          source_call.try { |value| value.id == argument.id } || false,
        }
      end
  end

  def __test_emitted_named_block_application_calls(
    method_name : String,
    source_def : Adamas::Compiler::Frontend::DefNode,
    source_arena : Adamas::Compiler::Frontend::ArenaLike,
  )
    main = @module.function_by_name("__adamas_main") || raise "missing lowered main"
    calls = main.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
      .select { |call| call.method_name.includes?("##{method_name}") }
    calls.map do |call|
      name = call.method_name
      registered_def = @function_defs[name]?
      registered_arena = @function_def_arenas[name]?
      {
        name,
        get_type_name_from_ref(call.type),
        function_namespace_override_for(name) || "",
        function_type_param_map_for_name(name).try { |map| map["T"]? } || "",
        registered_def.try { |definition| definition.same?(source_def) } || false,
        registered_arena.try { |arena| arena.object_id == source_arena.object_id } || false,
      }
    end
  end

  def __test_included_module_map_for_origin(owner : String, module_owner : String, application : String)
    included_module_type_param_map_for_origin(owner, module_owner, application)
  end

  def __test_generic_mro_included_origin(template : String, args : Array(String), owner : String, method_name : String)
    monomorphize_generic_class(template, args, owner)
    __test_mro_included_origin(owner, method_name, true)
  end

  def __test_generic_mro_included_origin_and_projection(
    template : String,
    args : Array(String),
    owner : String,
    method_name : String,
  )
    monomorphize_generic_class(template, args, owner)
    projection = source_generic_class_includes(owner)
    origin = __test_mro_included_origin(owner, method_name, true)
    {projection, origin}
  end

  private def __test_direct_include_application(receiver : String, module_base : String) : String?
    source_direct_class_includes(receiver).try do |applications|
      applications.find do |application|
        (split_generic_base_and_args(application).try(&.base) || application) == module_base
      end
    end
  end

  def __test_lexical_publication(owner : String) : Hash(String, String)
    monomorphize_generic_class("LexicalOuter::Host", ["Int32"], owner)

    nested = find_module_def_recursive_with_owner(
      "LexicalOuter::Host::Mixin", "lexical_marker", 0, Set(String).new, nil, true,
    ).not_nil!
    outer = find_module_def_recursive_with_owner(
      "LexicalOuter::Mixin", "lexical_marker", 0, Set(String).new, nil, true,
    ).not_nil!

    owner_base = strip_generic_args(owner)
    source_targets = @source_class_include_targets[owner_base]?.try do |targets|
      targets.map { |entry| resolve_path_like_name_in_arena(entry.target, entry.arena) || "<unresolved>" }.join("|")
    end || ""
    resolved_direct_targets = source_direct_class_includes(owner).try(&.join("|")) || "<nil>"
    registered_owner_modules = @class_included_modules[owner]?.try(&.join("|")) || ""
    registered_base_modules = @class_included_modules[owner_base]?.try(&.join("|")) || ""
    deferred_contexts = @deferred_module_contexts[owner]?.try do |contexts|
      contexts.map do |context|
        nested_arena = context.mod_arena.object_id == nested[1].object_id
        outer_arena = context.mod_arena.object_id == outer[1].object_id
        snapshot = context.type_param_snapshot.map { |name, value| "#{name}=#{value}" }.sort.join(",")
        "#{context.module_full_name}:namespace=#{context.namespace_override || "<nil>"}:params=#{context.type_param_names.join(",")}:snapshot=#{snapshot}:nested_arena=#{nested_arena}:outer_arena=#{outer_arena}"
      end.join("|")
    end || "<nil>"

    receiver_defs_before_lookup = [] of String
    @function_defs.each do |name, definition|
      parts = parse_method_name_compact(name)
      next unless parts.method == "lexical_marker"
      next unless strip_generic_args(parts.owner) == owner_base
      arena = @function_def_arenas[name]?
      nested_def = definition.same?(nested[0])
      outer_def = definition.same?(outer[0])
      nested_def_arena = arena.try { |candidate| candidate.object_id == nested[1].object_id } || false
      outer_def_arena = arena.try { |candidate| candidate.object_id == outer[1].object_id } || false
      namespace = function_namespace_override_for(name) || "<nil>"
      receiver_defs_before_lookup << "#{name}:namespace=#{namespace}:nested_def=#{nested_def}:nested_arena=#{nested_def_arena}:outer_def=#{outer_def}:outer_arena=#{outer_def_arena}"
    end
    receiver_defs_before_lookup.sort!

    ensure_method_index_built
    indexed = @method_index[method_index_owner_key(owner)]?.try do |methods|
      methods["lexical_marker"]?.try(&.all_candidates.join("|")) || ""
    end || ""
    selected = lookup_function_def_for_call(
      "#{owner}#lexical_marker", 0, true, [] of TypeRef, false, false,
    )
    selected_name = selected.try(&.[0])
    selected_def = selected.try(&.[1])
    selected_arena = selected_name.try { |name| @function_def_arenas[name]? }

    receiver_defs_after_lookup = [] of String
    @function_defs.each do |name, definition|
      parts = parse_method_name_compact(name)
      next unless parts.method == "lexical_marker"
      next unless strip_generic_args(parts.owner) == owner_base
      arena = @function_def_arenas[name]?
      nested_def = definition.same?(nested[0])
      outer_def = definition.same?(outer[0])
      nested_def_arena = arena.try { |candidate| candidate.object_id == nested[1].object_id } || false
      outer_def_arena = arena.try { |candidate| candidate.object_id == outer[1].object_id } || false
      namespace = function_namespace_override_for(name) || "<nil>"
      receiver_defs_after_lookup << "#{name}:namespace=#{namespace}:nested_def=#{nested_def}:nested_arena=#{nested_def_arena}:outer_def=#{outer_def}:outer_arena=#{outer_def_arena}"
    end
    receiver_defs_after_lookup.sort!

    {
      "source_target_spelling"     => source_targets,
      "resolved_direct_targets"    => resolved_direct_targets,
      "registered_owner_modules"   => registered_owner_modules,
      "registered_base_modules"    => registered_base_modules,
      "deferred_contexts"          => deferred_contexts,
      "receiver_defs_before_lookup" => receiver_defs_before_lookup.join("|"),
      "method_index_candidates"    => indexed,
      "selected_name"              => selected_name || "<nil>",
      "selected_owner"             => selected_name.try { |name| parse_method_name_compact(name).owner } || "<nil>",
      "selected_namespace"         => selected_name.try { |name| function_namespace_override_for(name) } || "<nil>",
      "selected_is_nested_def"     => (selected_def.try { |definition| definition.same?(nested[0]) } || false).to_s,
      "selected_arena_is_nested"   => (selected_arena.try { |arena| arena.same?(nested[1]) } || false).to_s,
      "selected_is_outer_def"      => (selected_def.try { |definition| definition.same?(outer[0]) } || false).to_s,
      "selected_arena_is_outer"    => (selected_arena.try { |arena| arena.same?(outer[1]) } || false).to_s,
      "receiver_defs_after_lookup"  => receiver_defs_after_lookup.join("|"),
      "nested_module_owner"        => nested[2],
      "outer_module_owner"         => outer[2],
      "nested_def_line"            => nested[0].span.start_line.to_s,
      "outer_def_line"             => outer[0].span.start_line.to_s,
    }
  end

  def __test_repair_stale_mro_target(receiver : String, earlier_module : String)
    receiver_type = type_ref_for_name(receiver)
    earlier = find_module_def_recursive_with_owner(
      earlier_module,
      "marker",
      0,
      Set(String).new,
      nil,
      true,
    ).not_nil!
    application = __test_direct_include_application(receiver, earlier_module).not_nil!
    earlier_origin = {earlier[0], earlier[1], earlier[2], application}
    name, definition = register_included_module_call_target(
      receiver,
      "marker",
      [] of TypeRef,
      true,
      earlier_origin,
    )
    selected = SelectedCallTarget.new(name, definition, earlier[1])
    corrected = rebase_selected_included_block_target_for_receiver(
      receiver,
      receiver_type,
      "marker",
      [] of TypeRef,
      selected,
    )
    {
      corrected.try(&.symbol_name),
      corrected.try(&.def_node),
      corrected.try(&.source_arena),
      corrected.try { |target| function_namespace_override_for(target.symbol_name) },
    }
  end

  def __test_direct_generic_method_rebase(receiver : String, method_name : String)
    monomorphize_generic_class("MroGenericDirect", ["Int32"], receiver)
    receiver_type = type_ref_for_name(receiver)
    name = mangle_function_name("#{receiver}##{method_name}", [] of TypeRef, true)
    definition = @function_defs[name]?
    arena = @function_def_arenas[name]?
    return {name, false, function_namespace_override_for(name), nil} unless definition && arena

    direct_definition : Adamas::Compiler::Frontend::DefNode? = nil
    templates = [] of GenericClassTemplate
    if template = @generic_templates[strip_generic_args(receiver)]?
      templates << template
    end
    if reopenings = @generic_reopenings[strip_generic_args(receiver)]?
      templates.concat(reopenings)
    end
    templates.reverse_each do |template|
      with_arena(template.arena) do
        if body = template.node.body
          body.reverse_each do |member_id|
            member = unwrap_visibility_member(@arena[member_id])
            if member.is_a?(Adamas::Compiler::Frontend::DefNode) &&
               (safe_slice_to_string(member.name) || "") == method_name
              direct_definition = member
              break
            end
          end
        end
      end
      break if direct_definition
    end

    selected = SelectedCallTarget.new(name, definition, arena)
    rebased = rebase_selected_included_block_target_for_receiver(
      receiver,
      receiver_type,
      method_name,
      [] of TypeRef,
      selected,
    )
    direct_match = if expected = direct_definition
                     definition.same?(expected)
                   else
                     false
                   end
    {name, direct_match, function_namespace_override_for(name), rebased.try(&.def_node)}
  end

  def __test_reject_replacing_lowered_mro_target(receiver : String) : {Bool, Bool}
    type_ref_for_name(receiver)
    earlier = find_module_def_recursive_with_owner(
      "TupleNestedPrior",
      "nested_marker",
      0,
      Set(String).new,
      nil,
      true,
    ).not_nil!
    winner = find_included_module_def_origin_for_owner(
      receiver,
      "nested_marker",
      0,
      true,
      respect_direct_declarations: false,
      compatible_arg_types: [] of TypeRef,
    ).not_nil!
    name = mangle_function_name("#{receiver}#nested_marker", [] of TypeRef, true)
    set_function_def_entry(name, earlier[0], false)
    set_function_def_arena(name, earlier[1])
    store_function_namespace_override(name, "#{receiver}#nested_marker", earlier[2], store_base: false)
    function = @module.create_function(name, TypeRef::VOID)
    function.get_block(function.entry_block).terminator = Return.new(nil)
    body_before = @module.has_function_with_body?(name)
    return {false, false} unless body_before
    begin
      register_included_module_call_target(receiver, "nested_marker", [] of TypeRef, true, winner)
      {false, @module.has_function_with_body?(name)}
    rescue error : LoweringError
      {error.message.try(&.includes?("after its HIR body was lowered")) || false, @module.has_function_with_body?(name)}
    end
  end
end

private def source_applied_include_mro_converter
  source = <<-CRYSTAL
    module TuplePrior(E)
      def marker(& : E ->) : Int32
        65
      end
    end
    module TupleLast(E)
      def marker(& : E ->) : Int32
        66
      end
    end
    module AppliedNoArg(T)
      def selected_type : T
        raise "HIR lookup only; this method must not execute"
      end
    end
    class AppliedMroHost
      include TuplePrior(Int32)
      include TupleLast(Int64)
    end
    class AppliedNoArgHost
      include AppliedNoArg(Int32)
      include AppliedNoArg(Int64)
    end
    module TupleNestedPrior(E)
      def nested_marker(& : E ->) : Int32
        65
      end
    end
    module TupleNestedLast(E)
      def nested_marker(& : E ->) : Int32
        66
      end
    end
    module TupleNestedWrapper(E)
      include TupleNestedPrior(E)
      include TupleNestedLast(E)
    end
    module TupleReopenedPrior(E)
      def reopened_marker(& : E ->) : Int32
        67
      end
    end
    module TupleReopenedLast(E)
      def reopened_marker(& : E ->) : Int32
        68
      end
    end
    module TupleReopenedWrapper(E)
      include TupleReopenedPrior(E)
    end
    module TupleReopenedWrapper(E)
      include TupleReopenedLast(E)
    end
    module LexicalOuter
      module Mixin(U)
        def lexical_marker(& : U ->) : Int32
          101
        end
      end
      class Host(T)
        module Mixin(U)
          def lexical_marker(& : U ->) : Int32
            202
          end
        end
        include Mixin(T)
      end
      class NonGenericHost
        module Mixin(U)
          def lexical_marker(& : U ->) : Int32
            303
          end
        end
        include Mixin(Int32)
      end
    end
    module MroFieldOrder
      @first : Int32
      @second : Int64
    end
    struct MroFieldHost
      include MroFieldOrder
    end
    struct Tuple
      include TuplePrior(Union(*T))
      include TupleLast(Union(*T))
      include TupleNestedWrapper(Union(*T))
      include TupleReopenedWrapper(Union(*T))
    end

    module GenericDirectMarker
      def direct_marker(& : Int32 ->) : Int32
        65
      end
    end
    class MroGenericDirect(T)
      include GenericDirectMarker
    end
    class MroGenericDirect(T)
      def direct_marker(& : Int32 ->) : Int32
        99
      end
    end

    module ParentMarker
      def marker(& : Int32 ->) : Int32
        80
      end
    end
    module ChildPrior
      def marker(& : Int32 ->) : Int32
        81
      end
    end
    module ChildLast
      def marker(& : Int32 ->) : Int32
        82
      end
    end
    class MroParent
      include ParentMarker
    end
    class MroChild < MroParent
      include ChildPrior
      include ChildLast
    end
    class MroOverride
      include ChildPrior
      include ChildLast
      def marker(& : Int32 ->) : Int32
        99
      end
    end
    CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "/tmp/source_applied_include_mro.cr"})
  converter.no_prelude = true
  program.roots.each do |id|
    case node = arena[id]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    end
  end
  converter
end

private def source_applied_noarg_emission_converter(source_method : String = "selected_value")
  source = <<-CRYSTAL
    module AppliedNoArgResult(T)
      def selected_value : T
        @payload
      end
      def selected_inferred_value
        @payload.as(T)
      end
    end
    class Int64LastApplication
      @payload : Int64
      include AppliedNoArgResult(Int32)
      include AppliedNoArgResult(Int64)
    end
    class Int32LastApplication
      @payload : Int32
      include AppliedNoArgResult(Int64)
      include AppliedNoArgResult(Int32)
    end
    class AppliedNoArgFormalHost(E)
      include AppliedNoArgResult(E)
    end
    class F
    end
    class AppliedNoArgFormalShadowHost(F)
      include AppliedNoArgResult(F)
    end
    class AppliedNoArgRootHost(F)
      include AppliedNoArgResult(::F)
    end
    class AppliedNoArgConsumer
      def consume(value : Int32) : Int32
        value
      end
      def consume(value : Int64) : Int64
        value
      end
      def consume_inferred(value : Int32) : Int32
        value
      end
      def consume_inferred(value : Int64) : Int64
        value
      end
      def consume_parenthesized(value : Int32) : Int32
        value
      end
      def consume_parenthesized(value : Int64) : Int64
        value
      end
    end
    Int64LastApplication.new.selected_value
    Int32LastApplication.new.selected_value
    AppliedNoArgConsumer.new.consume(Int64LastApplication.new.selected_value)
    AppliedNoArgConsumer.new.consume(Int32LastApplication.new.selected_value)
    AppliedNoArgConsumer.new.consume_inferred(Int64LastApplication.new.selected_inferred_value)
    AppliedNoArgConsumer.new.consume_inferred(Int32LastApplication.new.selected_inferred_value)
    AppliedNoArgConsumer.new.consume_parenthesized(Int64LastApplication.new.selected_value())
    AppliedNoArgConsumer.new.consume_parenthesized(Int32LastApplication.new.selected_value())
    CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "/tmp/source_applied_include_noarg_emission.cr"})
  converter.no_prelude = true
  modules = [] of Adamas::Compiler::Frontend::ModuleNode
  classes = [] of Adamas::Compiler::Frontend::ClassNode
  main = [] of UInt64
  source_def : Adamas::Compiler::Frontend::DefNode? = nil
  program.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
      modules << node
      if String.new(node.name) == "AppliedNoArgResult"
        node.body.not_nil!.each do |member_id|
          if member = arena[member_id].as?(Adamas::Compiler::Frontend::DefNode)
            source_def = member if String.new(member.name) == source_method
          end
        end
      end
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
      classes << node
    else
      main << root_id.index.to_u64
    end
  end
  classes.each { |node| converter.lower_class(node) }
  modules.each { |node| converter.lower_module(node) }
  converter.lower_main(main)
  converter.flush_pending_functions
  {converter, source_def.not_nil!, arena}
end

private def source_applied_named_block_emission_converter
  # Keep this body non-yielding so the selected invocation remains an actual
  # HIR Call instead of being expanded through inline-yield lowering.
  source = <<-CRYSTAL
    module AppliedNamedBlockResult(T)
      def selected_block_value(value : T, current ignored : Int32, &callback : T -> T) : T
        value
      end
    end
    class NamedInt64LastApplication
      include AppliedNamedBlockResult(Int32)
      include AppliedNamedBlockResult(Int64)
    end
    class NamedInt32LastApplication
      include AppliedNamedBlockResult(Int64)
      include AppliedNamedBlockResult(Int32)
    end
    NamedInt64LastApplication.new.selected_block_value(64_i64, current: 0) { |value| value }
    NamedInt32LastApplication.new.selected_block_value(32, current: 0) { |value| value }
    CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "/tmp/source_applied_include_named_block_emission.cr"})
  converter.no_prelude = true
  modules = [] of Adamas::Compiler::Frontend::ModuleNode
  classes = [] of Adamas::Compiler::Frontend::ClassNode
  main = [] of UInt64
  source_def : Adamas::Compiler::Frontend::DefNode? = nil
  program.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
      modules << node
      if String.new(node.name) == "AppliedNamedBlockResult"
        node.body.not_nil!.each do |member_id|
          if member = arena[member_id].as?(Adamas::Compiler::Frontend::DefNode)
            source_def = member if String.new(member.name) == "selected_block_value"
          end
        end
      end
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
      classes << node
    else
      main << root_id.index.to_u64
    end
  end
  classes.each { |node| converter.lower_class(node) }
  modules.each { |node| converter.lower_module(node) }
  converter.lower_main(main)
  converter.flush_pending_functions
  {converter, source_def.not_nil!, arena}
end

describe "source-applied include MRO" do
  it "chooses the last source include and replaces a stale eager module target" do
    converter = source_applied_include_mro_converter
    origin = converter.__test_mro_included_origin("Tuple(Int32, Int64)", "marker", true)
    origin.should_not be_nil
    origin.not_nil![2].should eq("TupleLast")

    corrected_name, corrected_def, corrected_arena, corrected_namespace =
      converter.__test_repair_stale_mro_target("Tuple(Int32, Int64)", "TuplePrior")
    corrected_name.should eq("Tuple(Int32, Int64)#marker$block")
    corrected_def.should be(origin.not_nil![0])
    corrected_arena.should be(origin.not_nil![1])
    corrected_namespace.should eq("TupleLast")
  end

  it "retains generic arguments for direct includes on a nongeneric owner" do
    converter = source_applied_include_mro_converter
    converter.__test_source_direct_class_includes("AppliedMroHost").should eq([
      "TuplePrior(Int32)",
      "TupleLast(Int64)",
    ])

    origin = converter.__test_mro_included_origin("AppliedMroHost", "marker", true)
    origin.should_not be_nil
    origin.not_nil![2].should eq("TupleLast")
    origin.not_nil![3].should eq("TupleLast(Int64)")
  end

  it "binds a noarg generic result to the exact repeated include application" do
    converter = source_applied_include_mro_converter
    converter.__test_source_direct_class_includes("AppliedNoArgHost").should eq([
      "AppliedNoArg(Int32)",
      "AppliedNoArg(Int64)",
    ])

    origin = converter.__test_noarg_mro_included_origin("AppliedNoArgHost", "selected_type")
    origin.should_not be_nil
    origin.not_nil![2].should eq("AppliedNoArg")
    origin.not_nil![3].should eq("AppliedNoArg(Int64)")
    converter.__test_included_module_map_for_origin(
      "AppliedNoArgHost",
      origin.not_nil![2],
      origin.not_nil![3],
    ).should eq({"T" => "Int64"})
  end

  it "emits noarg calls with the selected repeated application type and source identity" do
    converter, source_def, source_arena = source_applied_noarg_emission_converter
    calls = converter.__test_emitted_noarg_application_calls(source_def, source_arena)
    # Direct and nested no-parentheses accesses plus explicit empty calls all
    # retain the selected source application and its definition identity.
    calls.size.should eq(6)
    calls.map(&.[0]).should eq(["Int64", "Int32", "Int64", "Int32", "Int64", "Int32"])
    calls.map(&.[1]).should eq(Array.new(6, "AppliedNoArgResult"))
    calls.map(&.[2]).should eq(["Int64", "Int32", "Int64", "Int32", "Int64", "Int32"])
    calls.map(&.[3]).should eq(Array.new(6, true))
    calls.map(&.[4]).should eq(Array.new(6, true))
  end

  it "consumes noarg include results with their selected concrete return type" do
    converter, _, _ = source_applied_noarg_emission_converter
    calls = converter.__test_emitted_noarg_consumer_calls
    calls.size.should eq(2)
    calls.map { |call| call[0].ends_with?("$Int64") }.should eq([true, false])
    calls.map(&.[1]).should eq(["Int64", "Int32"])
    calls.map(&.[2]).should eq(["Int64", "Int32"])
    calls.map(&.[3]).should eq(["Int64", "Int32"])
    calls.map { |call| call[4].includes?("#selected_value") }.should eq([true, true])
    calls.map(&.[5]).should eq([true, true])
  end

  it "keeps explicit empty calls aligned with omitted-parentheses noarg selection" do
    converter, _, _ = source_applied_noarg_emission_converter
    calls = converter.__test_emitted_noarg_consumer_calls("consume_parenthesized")
    calls.size.should eq(2)
    calls.map { |call| call[0].ends_with?("$Int64") }.should eq([true, false])
    calls.map(&.[1]).should eq(["Int64", "Int32"])
    calls.map(&.[2]).should eq(["Int64", "Int32"])
    calls.map(&.[3]).should eq(["Int64", "Int32"])
    calls.map { |call| call[4].includes?("#selected_value") }.should eq([true, true])
    calls.map(&.[5]).should eq([true, true])
  end

  it "infers an unannotated noarg body under the exact repeated include application" do
    converter, source_def, source_arena = source_applied_noarg_emission_converter("selected_inferred_value")
    source_calls = converter.__test_emitted_noarg_application_calls(
      source_def,
      source_arena,
      "selected_inferred_value",
    )
    source_calls.size.should eq(2)
    source_calls.map(&.[0]).should eq(["Int64", "Int32"])
    source_calls.map(&.[1]).should eq(Array.new(2, "AppliedNoArgResult"))
    source_calls.map(&.[2]).should eq(["Int64", "Int32"])
    source_calls.map(&.[3]).should eq(Array.new(2, true))
    source_calls.map(&.[4]).should eq(Array.new(2, true))

    consumers = converter.__test_emitted_noarg_consumer_calls("consume_inferred")
    consumers.size.should eq(2)
    consumers.map { |call| call[0].ends_with?("$Int64") }.should eq([true, false])
    consumers.map(&.[1]).should eq(["Int64", "Int32"])
    consumers.map(&.[2]).should eq(["Int64", "Int32"])
    consumers.map(&.[3]).should eq(["Int64", "Int32"])
    consumers.map { |call| call[4].includes?("#selected_inferred_value") }.should eq([true, true])
    consumers.map(&.[5]).should eq([true, true])
  end

  it "keeps unresolved formal noarg results unknown but honors an explicit root type" do
    converter, _, _ = source_applied_noarg_emission_converter
    formal_origin = converter.__test_noarg_mro_included_origin(
      "AppliedNoArgFormalHost(E)",
      "selected_inferred_value",
      false,
    )
    formal_origin.should_not be_nil
    formal_origin.not_nil![3].should eq("AppliedNoArgResult(E)")
    converter.__test_included_module_map_for_origin(
      "AppliedNoArgFormalHost(E)",
      formal_origin.not_nil![2],
      formal_origin.not_nil![3],
    ).should eq({"T" => "E"})
    formal_result = converter.__test_noarg_source_call_return(
      "AppliedNoArgFormalHost(E)",
      "selected_inferred_value",
      Adamas::HIR::TypeRef::INT32,
    )
    formal_result.should_not be_nil
    formal_result.not_nil![0].should be_nil

    shadow_origin = converter.__test_noarg_mro_included_origin(
      "AppliedNoArgFormalShadowHost(F)",
      "selected_inferred_value",
      false,
    )
    shadow_origin.should_not be_nil
    shadow_origin.not_nil![3].should eq("AppliedNoArgResult(F)")
    converter.__test_included_module_map_for_origin(
      "AppliedNoArgFormalShadowHost(F)",
      shadow_origin.not_nil![2],
      shadow_origin.not_nil![3],
    ).should eq({"T" => "F"})
    shadow_result = converter.__test_noarg_source_call_return(
      "AppliedNoArgFormalShadowHost(F)",
      "selected_inferred_value",
      Adamas::HIR::TypeRef::INT32,
    )
    shadow_result.should_not be_nil
    shadow_result.not_nil![0].should be_nil

    root_origin = converter.__test_noarg_mro_included_origin(
      "AppliedNoArgRootHost(F)",
      "selected_value",
      false,
    )
    root_origin.should_not be_nil
    root_origin.not_nil![3].should eq("AppliedNoArgResult(::F)")
    converter.__test_included_module_map_for_origin(
      "AppliedNoArgRootHost(F)",
      root_origin.not_nil![2],
      root_origin.not_nil![3],
    ).should eq({"T" => "::F"})
    root_result = converter.__test_noarg_source_call_return(
      "AppliedNoArgRootHost(F)",
      "selected_value",
      Adamas::HIR::TypeRef::INT32,
    )
    root_result.should_not be_nil
    root_result.not_nil![0].should eq(converter.__test_type_ref("::F"))
    converter.__test_noarg_source_call_return(
      "NoSuchNoArgOwner",
      "selected_value",
      Adamas::HIR::TypeRef::INT32,
    ).should be_nil
  end

  it "emits named block calls with the selected repeated application type and source identity" do
    converter, source_def, source_arena = source_applied_named_block_emission_converter
    calls = converter.__test_emitted_named_block_application_calls(
      "selected_block_value", source_def, source_arena,
    )
    calls.size.should eq(2)
    int64_first_application = calls.map do |call|
      call[0].starts_with?("NamedInt64LastApplication#selected_block_value")
    end
    int32_first_application = calls.map do |call|
      call[0].starts_with?("NamedInt32LastApplication#selected_block_value")
    end
    int64_first_application.should eq([true, false])
    int32_first_application.should eq([false, true])
    calls.map { |call| call[0].includes?("_block_named_") }.should eq([true, true])
    calls.map(&.[1]).should eq(["Int64", "Int32"])
    calls.map(&.[2]).should eq(["AppliedNamedBlockResult", "AppliedNamedBlockResult"])
    calls.map(&.[3]).should eq(["Int64", "Int32"])
    calls.map(&.[4]).should eq([true, true])
    calls.map(&.[5]).should eq([true, true])
  end

  it "keeps the nearer class level ahead of ancestor includes" do
    converter = source_applied_include_mro_converter
    origin = converter.__test_mro_included_origin("MroChild", "marker", true)
    origin.should_not be_nil
    origin.not_nil![2].should eq("ChildLast")
  end

  it "resolves nested wrappers and reopened modules in reverse source include order" do
    converter = source_applied_include_mro_converter
    nested = converter.__test_mro_included_origin("Tuple(Int32, Int64)", "nested_marker", true)
    nested.should_not be_nil
    nested.not_nil![2].should eq("TupleNestedLast")

    reopened = converter.__test_mro_included_origin("Tuple(Int32, Int64)", "reopened_marker", true)
    reopened.should_not be_nil
    reopened.not_nil![2].should eq("TupleReopenedLast")
  end

  it "retires a stale namespace when a direct generic class reopening replaces an included method" do
    converter = source_applied_include_mro_converter
    name, direct_definition_selected, namespace, rebased =
      converter.__test_direct_generic_method_rebase("MroGenericDirect(Int32)", "direct_marker")
    name.should eq("MroGenericDirect(Int32)#direct_marker$block")
    direct_definition_selected.should be_true
    namespace.should be_nil
    rebased.should be_nil
  end

  it "resolves an unqualified include to the nested module before an enclosing namespace match" do
    converter = source_applied_include_mro_converter
    projection, origin = converter.__test_generic_mro_included_origin_and_projection(
      "LexicalOuter::Host",
      ["Int32"],
      "LexicalOuter::Host(Int32)",
      "lexical_marker",
    )
    projection.should eq([
      "LexicalOuter::Host::Mixin(Int32)",
    ])
    origin.should_not be_nil
    origin.not_nil![2].should eq("LexicalOuter::Host::Mixin")
  end

  it "retains a nongeneric nested include application and its lexical module identity" do
    converter = source_applied_include_mro_converter
    converter.__test_source_direct_class_includes("LexicalOuter::NonGenericHost").should eq([
      "LexicalOuter::NonGenericHost::Mixin(Int32)",
    ])

    origin = converter.__test_mro_included_origin("LexicalOuter::NonGenericHost", "lexical_marker", true)
    origin.should_not be_nil
    origin.not_nil![2].should eq("LexicalOuter::NonGenericHost::Mixin")
    origin.not_nil![3].should eq("LexicalOuter::NonGenericHost::Mixin(Int32)")
  end

  it "publishes the nested lexical module Def for a concrete receiver" do
    facts = source_applied_include_mro_converter.__test_lexical_publication("LexicalOuter::Host(Int32)")
    facts["source_target_spelling"].should eq("Mixin")
    facts["resolved_direct_targets"].should eq("LexicalOuter::Host::Mixin(Int32)")
    facts["receiver_defs_before_lookup"].should eq("")
    facts["selected_is_nested_def"].should eq("true")
    facts["selected_arena_is_nested"].should eq("true")
    facts["selected_namespace"].should eq("LexicalOuter::Host::Mixin")
    facts["selected_is_outer_def"].should eq("false")
  end

  it "keeps nil and non-empty all-Void argument vectors unknown while preserving exact zero-arg calls" do
    converter = source_applied_include_mro_converter
    converter.__test_unknown_call_arg_types(nil).should be_nil
    converter.__test_unknown_call_arg_types([] of Adamas::HIR::TypeRef).should be_false
    converter.__test_unknown_call_arg_types([Adamas::HIR::TypeRef::VOID]).should be_true
    converter.__test_unknown_call_arg_types([Adamas::HIR::TypeRef::INT32]).should be_false
  end

  it "fails closed when a lowered included target has no replay proof" do
    converter = source_applied_include_mro_converter
    rejected, body_preserved = converter.__test_reject_replacing_lowered_mro_target("Tuple(Int32, Int64)")
    rejected.should be_true
    body_preserved.should be_true
  end

  it "keeps included field layout in source declaration order" do
    converter = source_applied_include_mro_converter
    converter.__test_ivar_layout("MroFieldHost").map(&.[0]).should eq(["@first", "@second"])
  end

  it "does not let included modules replace a direct class method" do
    converter = source_applied_include_mro_converter
    converter.__test_mro_included_origin("MroOverride", "marker", true).should be_nil
  end
end
