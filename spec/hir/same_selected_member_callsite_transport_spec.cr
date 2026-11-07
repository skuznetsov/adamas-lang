require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_remember_same_selected_nilary_member_callsite(
    source_name : String,
    target_name : String,
    receiver_owner : String,
    member_name : String,
    selected_def : Adamas::Compiler::Frontend::DefNode,
    selected_arena : Adamas::Compiler::Frontend::ArenaLike,
    target_def : Adamas::Compiler::Frontend::DefNode? = nil,
    target_arena : Adamas::Compiler::Frontend::ArenaLike? = nil,
    registered_source_def : Adamas::Compiler::Frontend::DefNode? = nil,
    arg_types : Array(TypeRef) = [] of TypeRef,
    target_has_block : Bool = false,
    primitive_template : Bool = false,
    raw_callback : Bool = false,
  ) : Tuple(Bool, Bool, Bool, Array(TypeRef)?, Bool, Bool)
    @function_defs[source_name] = registered_source_def || selected_def
    @function_def_arenas[source_name] = selected_arena
    @function_defs[target_name] = target_def || selected_def
    @function_def_arenas[target_name] = target_arena || selected_arena
    if primitive_template
      @primitive_template_source_bindings[source_name] = PrimitiveTemplateSourceBinding.new(
        source_name, selected_def, selected_arena, "Array", "Array",
      )
    end
    if raw_callback
      callsite = CallsiteArgs.new(
        [] of TypeRef, nil, nil, true, selected_target: source_name,
      )
      @raw_callback_source_bindings[source_name] = RawCallbackSourceBinding.new(
        selected_def, selected_arena, callsite,
      )
    end

    remember_callsite_arg_types(source_name, arg_types)
    source_before = @pending_arg_types[source_name]?
    remember_callsite_arg_types(target_name, [] of TypeRef, has_block: true) if target_has_block
    accepted = remember_same_selected_nilary_member_callsite(
      source_name, target_name, receiver_owner, member_name,
      selected_def, selected_arena, arg_types,
    )
    source_after = @pending_arg_types[source_name]?
    source_shape_preserved = if before = source_before
                               if after = source_after
                                 expected = CallsiteArgs.new([] of TypeRef, nil, nil)
                                 same_callsite_args_shell?(before, after) &&
                                   same_callsite_args_shell?(before, expected)
                               else
                                 false
                               end
                             else
                               false
                             end
    target = @pending_arg_types[target_name]?
    expected_target = CallsiteArgs.new([] of TypeRef, nil, nil)
    target_shape_matches = target.try { |callsite| same_callsite_args_shell?(callsite, expected_target) } == true
    {accepted, @pending_arg_types.has_key?(source_name), !target.nil?, target.try(&.types), source_shape_preserved, target_shape_matches}
  end
end

private def same_selected_nilary_member_callsite_fixture
  source = <<-CRYSTAL
    def selected_source : Nil
      nil
    end
    def different_source : Nil
      nil
    end
    CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  parsed = parser.parse_program
  parser.diagnostics.should be_empty
  definitions = parsed.roots.compact_map do |id|
    parsed.ast_arena[id].as?(Adamas::Compiler::Frontend::DefNode)
  end
  converter = Adamas::HIR::AstToHir.new(
    parsed.ast_arena,
    sources_by_arena: {parsed.ast_arena.object_id.to_u64 => source},
  )
  converter.no_prelude = true
  {converter, definitions[0], definitions[1], parsed.ast_arena}
end

private def same_selected_nilary_member_callsite_names
  source = "Array(Proc(Int32, Nil | Exception, Nil))#pop?"
  target = "Array(Proc(::Int32, ::Nil | ::Exception, ::Nil))#pop?"
  receiver = "Array(Proc(::Int32, ::Nil | ::Exception, ::Nil))"
  {source, target, receiver}
end

describe "exact nilary member callsite transport" do
  it "rekeys the observed empty callshape only for the same selected canonical receiver" do
    converter, selected_def, _, arena = same_selected_nilary_member_callsite_fixture
    source, target, receiver = same_selected_nilary_member_callsite_names

    accepted, source_kept, target_present, target_types, source_shape_preserved, target_shape_matches = converter.__test_remember_same_selected_nilary_member_callsite(
      source, target, receiver, "pop?", selected_def, arena,
    )

    accepted.should be_true
    source_kept.should be_true
    target_present.should be_true
    target_types.should eq([] of Adamas::HIR::TypeRef)
    source_shape_preserved.should be_true
    target_shape_matches.should be_true
  end

  it "rejects a target key registered to a different Def or Arena" do
    converter, selected_def, other_def, arena = same_selected_nilary_member_callsite_fixture
    _, other_arena_def, _, other_arena = same_selected_nilary_member_callsite_fixture
    source, target, receiver = same_selected_nilary_member_callsite_names

    wrong_def = converter.__test_remember_same_selected_nilary_member_callsite(
      source, target, receiver, "pop?", selected_def, arena, target_def: other_def,
    )
    wrong_def[0].should be_false

    wrong_arena = converter.__test_remember_same_selected_nilary_member_callsite(
      source, target, receiver, "pop?", selected_def, arena, target_arena: other_arena,
    )
    wrong_arena[0].should be_false

    stale_source = converter.__test_remember_same_selected_nilary_member_callsite(
      source, target, receiver, "pop?", selected_def, arena, registered_source_def: other_arena_def,
    )
    stale_source[0].should be_false
  end

  it "rejects a different concrete owner and nonempty arity" do
    converter, selected_def, _, arena = same_selected_nilary_member_callsite_fixture
    source, target, receiver = same_selected_nilary_member_callsite_names
    other_owner = "OtherArray(Proc(::Int32, ::Nil | ::Exception, ::Nil))"

    wrong_owner = converter.__test_remember_same_selected_nilary_member_callsite(
      source, target, other_owner, "pop?", selected_def, arena,
    )
    wrong_owner[0].should be_false

    one_arg = converter.__test_remember_same_selected_nilary_member_callsite(
      source, target, receiver, "pop?", selected_def, arena,
      arg_types: [Adamas::HIR::TypeRef::INT32],
    )
    one_arg[0].should be_false
    one_arg[3].should be_nil
  end

  it "rejects conflicting target shape, primitive-template, and raw-callback receipts" do
    converter, selected_def, _, arena = same_selected_nilary_member_callsite_fixture
    source, target, receiver = same_selected_nilary_member_callsite_names

    conflict = converter.__test_remember_same_selected_nilary_member_callsite(
      source, target, receiver, "pop?", selected_def, arena, target_has_block: true,
    )
    conflict[0].should be_false

    primitive_converter, primitive_def, _, primitive_arena = same_selected_nilary_member_callsite_fixture
    primitive = primitive_converter.__test_remember_same_selected_nilary_member_callsite(
      source, target, receiver, "pop?", primitive_def, primitive_arena, primitive_template: true,
    )
    primitive[0].should be_false

    raw_converter, raw_def, _, raw_arena = same_selected_nilary_member_callsite_fixture
    raw_callback = raw_converter.__test_remember_same_selected_nilary_member_callsite(
      source, target, receiver, "pop?", raw_def, raw_arena, raw_callback: true,
    )
    raw_callback[0].should be_false
  end

  it "rejects a different method and a typed target suffix" do
    converter, selected_def, _, arena = same_selected_nilary_member_callsite_fixture
    source, target, receiver = same_selected_nilary_member_callsite_names

    wrong_method = converter.__test_remember_same_selected_nilary_member_callsite(
      source, target, receiver, "empty?", selected_def, arena,
    )
    wrong_method[0].should be_false

    suffixed_converter, suffixed_def, _, suffixed_arena = same_selected_nilary_member_callsite_fixture
    typed_target = "#{target}$Int32"
    typed_suffix = suffixed_converter.__test_remember_same_selected_nilary_member_callsite(
      source, typed_target, receiver, "pop?", suffixed_def, suffixed_arena,
    )
    typed_suffix[0].should be_false
  end
end
