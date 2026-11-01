require "../spec_helper"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
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
    converter = conflicting_applied_include_converter
    projections, persisted_leaf_application, bindings = converter.__test_conflicting_applied_include_lookup("Tuple(Int32)")
    projections.should contain("AppliedLeaf(Int32)")
    projections.should contain("AppliedLeaf(Int64)")
    persisted_leaf_application.should be_false
    bindings.should be_nil
  end
end
