require "../spec_helper"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_concrete_included_receiver(receiver_type : TypeRef, receiver_name : String) : Bool
    concrete_included_method_receiver?(receiver_type, receiver_name)
  end

  def __test_tuple_receiver_admission(receiver : String, bindings : Hash(String, String)) : Bool
    with_isolated_type_param_map(bindings) do
      receiver_type = type_ref_for_name(receiver)
      concrete_included_method_receiver?(receiver_type, receiver)
    end
  end

  def __test_applied_include_lookup(receiver : String)
    type_ref_for_name(receiver)
    persisted_leaf_application = persisted_module_application?(receiver, "AppliedLeaf")
    projections = source_generic_ancestor_projections(receiver)
    lookup = with_isolated_type_param_map({"E" => "Bool"}) do
      bindings = included_module_type_param_map(receiver, "AppliedLeaf")
      found = find_included_module_def_for_owner(receiver, "probe", [] of TypeRef, true)
      target = if found
        name, _ = register_included_module_call_target(receiver, "probe", [] of TypeRef, true, found)
        {name, @function_defs[name]?, @function_def_arenas[name]?, function_namespace_override_for(name), function_type_param_map_for_name(name)}
      end
      {bindings, target, @type_param_map["E"]?}
    end
    {projections, persisted_leaf_application, lookup}
  end

  def __test_conflicting_applied_include_lookup(receiver : String)
    type_ref_for_name(receiver)
    persisted_leaf_application = persisted_module_application?(receiver, "AppliedLeaf")
    projections = source_generic_ancestor_projections(receiver)
    bindings = included_module_type_param_map(receiver, "AppliedLeaf")
    {projections, persisted_leaf_application, bindings}
  end

  def __test_repeated_generic_include_binding(
    receiver : String,
    value_type_name : String,
  ) : Tuple(String?, String?, String?, Bool, Bool)
    type_ref_for_name(receiver)
    value_type = type_ref_for_name(value_type_name)
    int32_type = type_ref_for_name("Int32")
    input = CallResolutionInput.new(
      func_name: "#{receiver}#marker",
      arg_count: 2,
      arg_types: [value_type, int32_type],
      has_block: true,
      has_splat: false,
      has_named: true,
      named_names: ["current"],
      raw_positional_count: 1,
      source_named_types: true,
    )
    found = find_included_module_def_origin_for_owner(
      receiver,
      "marker",
      input.arg_count,
      input.has_block,
      respect_direct_declarations: false,
      compatible_arg_types: input.arg_types,
      selection_input: input,
    )
    return {nil, nil, nil, false, false} unless found

    name, definition = register_included_module_call_target(
      receiver,
      "marker",
      input.arg_types.not_nil!,
      input.has_block,
      found,
      input,
    )
    bindings = function_type_param_map_for_name(name)
    registered_definition_matches = @function_defs[name]?.try do |registered|
      same_def_node?(registered, definition)
    end || false
    {
      found[3],
      bindings.try { |map| map["T"]? },
      function_namespace_override_for(name),
      call_target_matches_call_shape?(input, definition),
      registered_definition_matches,
    }
  end

  def __test_repeated_generic_result_binding(receiver : String) : Tuple(String?, String?, String?)
    type_ref_for_name(receiver)
    input = CallResolutionInput.new(
      func_name: "#{receiver}#result",
      arg_count: 0,
      arg_types: [] of TypeRef,
      has_block: false,
      has_splat: false,
      has_named: false,
      named_names: nil,
    )
    found = find_included_module_def_origin_for_owner(
      receiver,
      "result",
      0,
      false,
      respect_direct_declarations: false,
      compatible_arg_types: [] of TypeRef,
      selection_input: input,
    )
    return {nil, nil, nil} unless found

    name, _ = register_included_module_call_target(
      receiver,
      "result",
      [] of TypeRef,
      false,
      found,
      input,
    )
    {found[3], function_type_param_map_for_name(name).try { |map| map["T"]? }, name}
  end

  def __test_conflicting_transitive_source_origin(
    receiver : String,
    expected_definition : Adamas::Compiler::Frontend::DefNode,
    expected_arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Tuple(String?, String?, String?, Bool, Bool)
    type_ref_for_name(receiver)
    found = with_isolated_type_param_map({"E" => "Bool"}) do
      find_included_module_def_origin_for_owner(
        receiver,
        "probe",
        0,
        true,
        respect_direct_declarations: false,
        compatible_arg_types: [] of TypeRef,
      )
    end
    return {nil, nil, nil, false, false} unless found

    bindings = included_module_type_param_map_for_origin(receiver, found[2], found[3])
    {
      found[2],
      found[3],
      bindings.try { |map| map["E"]? },
      same_def_node?(found[0], expected_definition),
      found[1].object_id == expected_arena.object_id,
    }
  end

  private def persisted_module_application?(receiver : String, owner_base : String) : Bool
    applications = @class_include_instantiations[receiver]? || [] of String
    applications.any? do |application|
      split_generic_base_and_args(application).try(&.base) == owner_base
    end
  end
end

private def applied_include_converter
  source = <<-CRYSTAL
    module AppliedLeaf(E)
      def probe(& : E ->) : Bool
        true
      end
    end
    module AppliedMiddle(U)
      include AppliedLeaf(U)
    end
    module Foo
      class T
      end
    end
    struct Tuple
      include AppliedMiddle(Union(*T))
    end
    CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "/tmp/source_applied_include_lookup.cr"})
  converter.no_prelude = true
  source_def = nil.as(Adamas::Compiler::Frontend::DefNode?)
  program.roots.each do |id|
    case node = arena[id]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
      if String.new(node.name) == "AppliedLeaf"
        node.body.not_nil!.each do |member_id|
          if member = arena[member_id].as?(Adamas::Compiler::Frontend::DefNode)
            source_def = member
          end
        end
      end
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    end
  end
  {converter, source_def.not_nil!, arena}
end

private def conflicting_applied_include_converter
  source = <<-CRYSTAL
    module AppliedLeaf(E)
      def probe(& : E ->) : Bool
        true
      end
    end
    module AppliedLeft
      include AppliedLeaf(Int32)
    end
    module AppliedRight
      include AppliedLeaf(Int64)
    end
    struct Tuple
      include AppliedLeft
      include AppliedRight
    end
    CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "/tmp/source_applied_include_conflict.cr"})
  converter.no_prelude = true
  source_def = nil.as(Adamas::Compiler::Frontend::DefNode?)
  program.roots.each do |id|
    case node = arena[id]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
      if String.new(node.name) == "AppliedLeaf"
        node.body.not_nil!.each do |member_id|
          source_def = arena[member_id].as?(Adamas::Compiler::Frontend::DefNode)
        end
      end
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    end
  end
  {converter, source_def.not_nil!, arena}
end

private def repeated_generic_module_include_converter
  source = <<-CRYSTAL
    module RepeatedMroBinding(T)
      def result : T
        1
      end

      def marker(value : T, current ignored : Int32, & : T -> T) : T
        yield value
      end
    end
    class RepeatedMroForward
      include RepeatedMroBinding(Int32)
      include RepeatedMroBinding(Int64)
    end
    class RepeatedMroReverse
      include RepeatedMroBinding(Int64)
      include RepeatedMroBinding(Int32)
    end
    class RepeatedMroGenericOwner(T)
      include RepeatedMroBinding(T)
      include RepeatedMroBinding(Int64)
    end
    CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "/tmp/repeated_generic_module_include.cr"})
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

describe "source-applied include lookup" do
  {"Tuple(Int32)" => "Int32", "Tuple(Int32, Int64)" => "Int32 | Int64"}.each do |receiver, element|
    it "recovers the leaf source binding for #{receiver} before module materialization" do
      converter, definition, arena = applied_include_converter
      projections, persisted_leaf_application, lookup = converter.__test_applied_include_lookup(receiver)
      bindings, target, ambient_e = lookup
      projections.should contain("AppliedLeaf(#{element})")
      persisted_leaf_application.should be_false
      ambient_e.should eq("Bool")
      bindings.should_not be_nil
      bindings.not_nil!["E"].should eq(element)
      target.should_not be_nil
      name, selected, selected_arena, namespace, target_map = target.not_nil!
      name.should eq("#{receiver}#probe$block")
      selected.should be(definition)
      selected_arena.should be(arena)
      namespace.should eq("AppliedLeaf")
      target_map.not_nil!["E"].should eq(element)
    end
  end

  it "rejects conflicting leaf bindings projected through a diamond" do
    converter, _, _ = conflicting_applied_include_converter
    projections, persisted_leaf_application, bindings = converter.__test_conflicting_applied_include_lookup("Tuple(Int32)")
    projections.should contain("AppliedLeaf(Int32)")
    projections.should contain("AppliedLeaf(Int64)")
    persisted_leaf_application.should be_false
    bindings.should be_nil
  end

  it "retains the exact generic module application for both argument types in either include order" do
    {
      {"RepeatedMroForward", "Int32", "RepeatedMroBinding(Int32)"},
      {"RepeatedMroForward", "Int64", "RepeatedMroBinding(Int64)"},
      {"RepeatedMroReverse", "Int32", "RepeatedMroBinding(Int32)"},
      {"RepeatedMroReverse", "Int64", "RepeatedMroBinding(Int64)"},
    }.each do |receiver, value_type, application|
      converter = repeated_generic_module_include_converter
      selected_application, binding, namespace, shape_matches, registered_def_matches =
        converter.__test_repeated_generic_include_binding(receiver, value_type)
      selected_application.should eq(application)
      binding.should eq(value_type)
      namespace.should eq("RepeatedMroBinding")
      shape_matches.should be_true
      registered_def_matches.should be_true
    end
  end

  it "uses the latest application for a same-ABI result-only declaration" do
    {
      {"RepeatedMroForward", "RepeatedMroBinding(Int64)", "Int64"},
      {"RepeatedMroReverse", "RepeatedMroBinding(Int32)", "Int32"},
    }.each do |receiver, application, result_type|
      converter = repeated_generic_module_include_converter
      selected_application, binding, target_name = converter.__test_repeated_generic_result_binding(receiver)
      selected_application.should eq(application)
      binding.should eq(result_type)
      target_name.should eq("#{receiver}#result")
    end
  end

  it "substitutes the concrete generic owner before comparing include applications" do
    converter = repeated_generic_module_include_converter
    {
      {"Int32", "RepeatedMroBinding(Int32)"},
      {"Int64", "RepeatedMroBinding(Int64)"},
    }.each do |value_type, application|
      selected_application, binding, namespace, shape_matches, registered_def_matches =
        converter.__test_repeated_generic_include_binding("RepeatedMroGenericOwner(Int32)", value_type)
      selected_application.should eq(application)
      binding.should eq(value_type)
      namespace.should eq("RepeatedMroBinding")
      shape_matches.should be_true
      registered_def_matches.should be_true
    end
  end

  it "selects the exact rightmost leaf application while aggregate projection stays ambiguous" do
    converter, definition, arena = conflicting_applied_include_converter
    owner, application, binding, same_definition, same_arena =
      converter.__test_conflicting_transitive_source_origin("Tuple(Int32)", definition, arena)

    owner.should eq("AppliedLeaf")
    application.should eq("AppliedLeaf(Int64)")
    binding.should eq("Int64")
    same_definition.should be_true
    same_arena.should be_true
  end
end


describe "Tuple concrete receiver admission" do
  it "admits concrete and empty builtin Tuple descriptors" do
    converter, _, _ = applied_include_converter
    converter.__test_tuple_receiver_admission("Tuple(Int32, Int64)", {} of String => String).should be_true
    converter.__test_tuple_receiver_admission("Tuple()", {} of String => String).should be_true
  end

  {"E", "Array(E)", "Tuple(E, Int32)"}.each do |element|
    it "rejects unresolved Tuple element #{element} under ambient self bindings" do
      converter, _, _ = applied_include_converter
      converter.__test_tuple_receiver_admission("Tuple(#{element})", {"E" => "E"}).should be_false
    end
  end

  it "does not admit a generic-looking name unless its resolved descriptor is Tuple" do
    converter, _, _ = applied_include_converter
    type_ref = Adamas::HIR::TypeRef::INT32
    converter.__test_concrete_included_receiver(type_ref, "Tuple(Int32)").should be_false
  end
end
