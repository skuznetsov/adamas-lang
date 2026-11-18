require "../spec_helper"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_transitive_marker_origin_contract(
    owner : String,
    value_type_name : String,
    module_suffix : String,
    supply_source_facts : Bool = true,
  ) : Tuple(String?, Hash(String, String)?, Bool, Bool, Bool, Bool)
    type_ref_for_name(owner)
    argument_types = [type_ref_for_name(value_type_name), TypeRef::INT32]
    facts = argument_types.map { |type| SourceCallArgument.new(type, false).as(SourceCallArgument?) } if supply_source_facts
    input = CallResolutionInput.new(
      func_name: "#{owner}#marker",
      arg_count: 2,
      arg_types: argument_types,
      has_block: true,
      has_splat: false,
      has_named: true,
      named_names: ["current"],
      raw_positional_count: 1,
      source_named_types: true,
      source_argument_facts: facts,
    )
    found = find_included_module_def_origin_for_owner(
      owner,
      "marker",
      input.arg_count,
      input.has_block,
      respect_direct_declarations: false,
      compatible_arg_types: input.arg_types,
      selection_input: input,
    )
    return {nil, nil, false, false, false, false} unless found

    source_def, source_arena = __test_transitive_marker_source(module_suffix)
    {
      found[3],
      included_module_type_param_map_for_origin(owner, found[2], found[3]),
      same_def_node?(found[0], source_def),
      found[1].object_id == source_arena.object_id,
      input.has_block,
      input.has_named,
    }
  end

  private def __test_transitive_marker_source(module_suffix : String) : Tuple(
    Adamas::Compiler::Frontend::DefNode,
    Adamas::Compiler::Frontend::ArenaLike,
  )
    @module_defs.each do |module_name, definitions|
      module_base = strip_generic_args(module_name)
      next unless module_base == module_suffix || module_base.ends_with?("::#{module_suffix}")

      definitions.each do |module_node, module_arena|
        marker = with_arena(module_arena) do
          module_node.body.try do |body|
            body.compact_map do |expr_id|
              member = unwrap_visibility_member(@arena[expr_id])
              next unless definition = member.as?(Adamas::Compiler::Frontend::DefNode)
              definition if safe_slice_to_string(definition.name) == "marker"
            end.first?
          end
        end
        return {marker, module_arena} if marker
      end
    end

    raise "missing #{module_suffix}#marker source"
  end
end

private def source_applied_transitive_block_converter : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    module TransitiveBlockLeaf(T)
      def marker(value : T, current ignored : Int32, &callback : T -> T) : T
        callback.call(value)
      end
    end
    module TransitiveBlockOuter(U)
      include TransitiveBlockLeaf(U)
    end
    class HostInt32ThenInt64
      include TransitiveBlockOuter(Int32)
      include TransitiveBlockOuter(Int64)
    end
    class HostInt64ThenInt32
      include TransitiveBlockOuter(Int64)
      include TransitiveBlockOuter(Int32)
    end
    HostInt32ThenInt64.new.marker(65, current: 0) { |value| value }
    HostInt32ThenInt64.new.marker(66_i64, current: 0) { |value| value }
    HostInt64ThenInt32.new.marker(65, current: 0) { |value| value }
    HostInt64ThenInt32.new.marker(66_i64, current: 0) { |value| value }
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "/tmp/source_applied_transitive_block_origin.cr"},
  )
  converter.no_prelude = true
  modules = [] of Adamas::Compiler::Frontend::ModuleNode
  classes = [] of Adamas::Compiler::Frontend::ClassNode
  main = [] of UInt64
  program.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
      modules << node
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
  converter
end

private def source_applied_nested_transitive_block_converter : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    module NestedTransitiveBlockLeaf(T)
      def marker(value : T, current ignored : Int32, &callback : T -> T) : T
        callback.call(value)
      end
    end
    module NestedTransitiveBlockInt32ThenInt64
      include NestedTransitiveBlockLeaf(Int32)
      include NestedTransitiveBlockLeaf(Int64)
    end
    module NestedTransitiveBlockInt64ThenInt32
      include NestedTransitiveBlockLeaf(Int64)
      include NestedTransitiveBlockLeaf(Int32)
    end
    class NestedHostInt32ThenInt64
      include NestedTransitiveBlockInt32ThenInt64
    end
    class NestedHostInt64ThenInt32
      include NestedTransitiveBlockInt64ThenInt32
    end
    NestedHostInt32ThenInt64.new.marker(65, current: 0) { |value| value }
    NestedHostInt32ThenInt64.new.marker(66_i64, current: 0) { |value| value }
    NestedHostInt64ThenInt32.new.marker(65, current: 0) { |value| value }
    NestedHostInt64ThenInt32.new.marker(66_i64, current: 0) { |value| value }
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "/tmp/source_applied_nested_transitive_block_origin.cr"},
  )
  converter.no_prelude = true
  modules = [] of Adamas::Compiler::Frontend::ModuleNode
  classes = [] of Adamas::Compiler::Frontend::ClassNode
  main = [] of UInt64
  program.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
      modules << node
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
  converter
end

describe "source-applied transitive generic block includes" do
  it "requires source value kinds for named-call admission" do
    converter = source_applied_transitive_block_converter
    converter.__test_transitive_marker_origin_contract(
      "HostInt32ThenInt64", "Int64", "TransitiveBlockLeaf", supply_source_facts: false,
    ).should eq({nil, nil, false, false, false, false})
  end

  it "projects the selected nested application to its exact generic binding" do
    converter = source_applied_transitive_block_converter
    converter.__test_transitive_marker_origin_contract(
      "HostInt32ThenInt64",
      "Int64",
      "TransitiveBlockLeaf",
    ).should eq({"TransitiveBlockLeaf(::Int64)", {"T" => "::Int64"}, true, true, true, true})

    converter = source_applied_transitive_block_converter
    converter.__test_transitive_marker_origin_contract(
      "HostInt64ThenInt32",
      "Int32",
      "TransitiveBlockLeaf",
    ).should eq({"TransitiveBlockLeaf(::Int32)", {"T" => "::Int32"}, true, true, true, true})
  end

  it "selects the exact source body and arena for block-shaped named calls" do
    converter = source_applied_transitive_block_converter
    converter.__test_transitive_marker_origin_contract("HostInt32ThenInt64", "Int32", "TransitiveBlockLeaf")
      .should eq({"TransitiveBlockLeaf(::Int32)", {"T" => "::Int32"}, true, true, true, true})
    converter.__test_transitive_marker_origin_contract("HostInt32ThenInt64", "Int64", "TransitiveBlockLeaf")
      .should eq({"TransitiveBlockLeaf(::Int64)", {"T" => "::Int64"}, true, true, true, true})
    converter.__test_transitive_marker_origin_contract("HostInt64ThenInt32", "Int32", "TransitiveBlockLeaf")
      .should eq({"TransitiveBlockLeaf(::Int32)", {"T" => "::Int32"}, true, true, true, true})
    converter.__test_transitive_marker_origin_contract("HostInt64ThenInt32", "Int64", "TransitiveBlockLeaf")
      .should eq({"TransitiveBlockLeaf(::Int64)", {"T" => "::Int64"}, true, true, true, true})
  end

  it "selects the compatible nested application within one outer module in both orders" do
    converter = source_applied_nested_transitive_block_converter
    converter.__test_transitive_marker_origin_contract(
      "NestedHostInt32ThenInt64",
      "Int32",
      "NestedTransitiveBlockLeaf",
    ).should eq({"NestedTransitiveBlockLeaf(Int32)", {"T" => "Int32"}, true, true, true, true})
    converter.__test_transitive_marker_origin_contract(
      "NestedHostInt32ThenInt64",
      "Int64",
      "NestedTransitiveBlockLeaf",
    ).should eq({"NestedTransitiveBlockLeaf(Int64)", {"T" => "Int64"}, true, true, true, true})
    converter.__test_transitive_marker_origin_contract(
      "NestedHostInt64ThenInt32",
      "Int32",
      "NestedTransitiveBlockLeaf",
    ).should eq({"NestedTransitiveBlockLeaf(Int32)", {"T" => "Int32"}, true, true, true, true})
    converter.__test_transitive_marker_origin_contract(
      "NestedHostInt64ThenInt32",
      "Int64",
      "NestedTransitiveBlockLeaf",
    ).should eq({"NestedTransitiveBlockLeaf(Int64)", {"T" => "Int64"}, true, true, true, true})
  end
end
