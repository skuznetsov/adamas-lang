require "../spec_helper"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_inherited_bare_physical_owner(
    parent_node : Adamas::Compiler::Frontend::ClassNode,
    parent_arena : Adamas::Compiler::Frontend::ArenaLike,
    child_node : Adamas::Compiler::Frontend::ClassNode,
    child_arena : Adamas::Compiler::Frontend::ArenaLike,
    lower_sibling_first : Bool,
    stale_source_super : Bool = false,
  )
    parent_name = "PhysicalOwnerParent#value"
    physical_name = "PhysicalOwnerChild#value"

    @arena = parent_arena
    register_class(parent_node)
    @arena = child_arena
    register_class(child_node)

    parent_def = @function_defs[parent_name]? || raise "missing parent value Def"
    shadow_def = @function_defs[physical_name]? || raise "missing child physical shadow Def"
    unless shadow_def.params.try(&.size) == 1 && def_params_untyped?(shadow_def)
      raise "child physical entry is not the expected untyped one-argument Def"
    end
    shadow_name = @function_defs.find do |registered_name, definition|
      registered_name != physical_name && definition.same?(shadow_def) &&
        registered_name.includes?("$arity1")
    end.try(&.[0]) || raise "missing child one-argument arity sibling"

    # Recreate the observed registry state: the child's required-argument Def
    # occupies the physical bare key, while the inherited nilary Def remains
    # registered under its source owner.
    set_function_def_entry(physical_name, shadow_def, record_current_arena: false)
    set_function_def_arena(physical_name, child_arena)
    if stale_source_super
      # Exercise the helper's fail-closed transaction guard: the source key
      # carries a super certificate for a different Def.
      @method_body_super_sources[parent_name] = {shadow_def, parent_arena, parent_name}
    end

    int32 = type_ref_for_name("Int32")
    lower_sibling = -> do
      remember_callsite_arg_types(shadow_name, [int32])
      lower_function_if_needed(shadow_name)
    end

    redirect_rejected = false
    redirect_error = nil.as(String?)
    if stale_source_super
      begin
        remember_callsite_arg_types(physical_name, [] of TypeRef)
        lower_function_if_needed(physical_name)
      rescue error : LoweringError
        redirect_rejected = true
        redirect_error = error.message
      end
    else
      lower_sibling.call if lower_sibling_first
      remember_callsite_arg_types(physical_name, [] of TypeRef)
      lower_function_if_needed(physical_name)
    end

    physical_def_matches_source = @function_defs[physical_name]?.try(&.same?(parent_def)) || false
    physical_arena_matches_source =
      @function_def_arenas[physical_name]?.try(&.object_id) == parent_arena.object_id
    sibling_def_survived = @function_defs[shadow_name]?.try(&.same?(shadow_def)) || false
    sibling_arena_survived =
      @function_def_arenas[shadow_name]?.try(&.object_id) == child_arena.object_id
    sibling_param_names = function_param_infos(shadow_name, shadow_def).map(&.name)

    lower_sibling.call unless lower_sibling_first

    physical = @module.function_by_name(physical_name)
    sibling = @module.function_by_name(shadow_name)
    physical_return = physical.try { |function| get_type_name_from_ref(function.return_type) }
    sibling_return = sibling.try { |function| get_type_name_from_ref(function.return_type) }
    physical_def_still_shadow = @function_defs[physical_name]?.try(&.same?(shadow_def)) || false
    physical_arena_still_shadow =
      @function_def_arenas[physical_name]?.try(&.object_id) == child_arena.object_id
    source_def_still_registered = @function_defs[parent_name]?.try(&.same?(parent_def)) || false
    source_arena_still_registered =
      @function_def_arenas[parent_name]?.try(&.object_id) == parent_arena.object_id
    lower_sibling.call if stale_source_super

    {
      physical_name,
      shadow_name,
      physical_def_matches_source,
      physical_arena_matches_source,
      sibling_def_survived,
      sibling_arena_survived,
      sibling_param_names,
      physical_return,
      sibling_return,
      redirect_rejected,
      physical_def_still_shadow,
      physical_arena_still_shadow,
      source_def_still_registered,
      source_arena_still_registered,
      redirect_error,
    }
  end
end

private def inherited_bare_physical_owner_case(
  lower_sibling_first : Bool,
  stale_source_super : Bool = false,
)
  parent_source = <<-CRYSTAL
    class PhysicalOwnerParent
      def value : UInt64
        9_u64
      end
    end
  CRYSTAL
  child_source = <<-CRYSTAL
    class PhysicalOwnerChild < PhysicalOwnerParent
      def value(item)
        item
      end
    end
  CRYSTAL

  parent_parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(parent_source)
  )
  parent_program = parent_parser.parse_program
  parent_parser.diagnostics.should be_empty
  parent_arena = parent_program.arena
  parent_node = parent_program.roots.compact_map do |root|
    parent_arena[root].as?(Adamas::Compiler::Frontend::ClassNode)
  end.first? || raise "missing parent class"

  child_parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(child_source)
  )
  child_program = child_parser.parse_program
  child_parser.diagnostics.should be_empty
  child_arena = child_program.arena
  child_node = child_program.roots.compact_map do |root|
    child_arena[root].as?(Adamas::Compiler::Frontend::ClassNode)
  end.first? || raise "missing child class"

  converter = Adamas::HIR::AstToHir.new(
    child_arena,
    sources_by_arena: {
      parent_arena.object_id.to_u64 => parent_source,
      child_arena.object_id.to_u64 => child_source,
    },
  )
  converter.no_prelude = true
  converter.__test_inherited_bare_physical_owner(
    parent_node, parent_arena, child_node, child_arena, lower_sibling_first,
    stale_source_super: stale_source_super
  )
end

describe "inherited bare physical body ownership" do
  {false => "bare body first", true => "typed sibling first"}.each do |lower_sibling_first, order|
    it "binds the selected parent body before lowering the #{order}" do
      result = inherited_bare_physical_owner_case(lower_sibling_first)

      result[2].should be_true
      result[3].should be_true
      result[4].should be_true
      result[5].should be_true
      result[6].should eq(["item"])
      result[7].should eq("UInt64")
      result[8].should eq("Int32")
    end
  end

  it "rejects a stale super certificate before changing the physical owner" do
    result = inherited_bare_physical_owner_case(false, stale_source_super: true)

    result[9].should be_true
    result[10].should be_true
    result[11].should be_true
    result[12].should be_true
    result[13].should be_true
    result[14].try(&.includes?("super source changed")).should be_true
  end
end
