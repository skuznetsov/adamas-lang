require "../spec_helper"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  private def __test_module_has_source_def?(module_name : String, expected_def : Adamas::Compiler::Frontend::DefNode,
                                            expected_arena : Adamas::Compiler::Frontend::ArenaLike) : Bool
    @module_defs[module_name]?.try do |definitions|
      definitions.any? do |module_node, module_arena|
        next false unless module_arena.object_id == expected_arena.object_id

        with_arena(module_arena) do
          module_node.body.try do |body|
            body.any? do |expr_id|
              member = unwrap_visibility_member(@arena[expr_id])
              member.as?(Adamas::Compiler::Frontend::DefNode).try do |definition|
                same_def_node?(definition, expected_def)
              end || false
            end
          end || false
        end
      end
    end || false
  end

  def __test_source_super_successor(
    owner : String,
    current_module : String,
    current_bindings : Hash(String, String),
    method_name : String,
  ) : Tuple(String?, String?, Bool, String?)
    function_name = "#{owner}##{method_name}_source_super_probe"
    @function_type_param_maps[function_name] = current_bindings
    order = source_super_module_applications_after_current(owner, current_module, function_name)
    return {nil, nil, false, nil} unless order
    return {nil, nil, false, nil} unless current_index = order[1]

    index = current_index + 1
    while index < order[0].size
      application = order[0].unsafe_fetch(index)
      if found = source_super_module_def_for_application(
           owner,
           application,
           method_name,
           1,
           [type_ref_for_name("Int32")],
         )
        registered_source = __test_module_has_source_def?(found[2], found[0], found[1])
        return {application, found[2], registered_source, source_path_for(found[1])}
      end
      index += 1
    end
    {nil, nil, false, nil}
  end
end

private def source_applied_super_mro_converter : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    module SourceSuperTailA
      def marker(value : Int32) : Int32
        65
      end
    end
    module SourceSuperTailB
      def marker(value : Int32) : Int32
        66
      end
    end
    module SourceSuperOrigin(T)
      def marker(value : T) : Int32
        super(value)
      end
    end
    module SourceSuperWrapperA
      include SourceSuperTailA
      include SourceSuperOrigin(Int32)
    end
    module SourceSuperWrapperB
      include SourceSuperTailB
      include SourceSuperOrigin(Int32)
    end
    class SourceSuperHostAB
      include SourceSuperWrapperA
      include SourceSuperWrapperB
    end
    class SourceSuperHostBA
      include SourceSuperWrapperB
      include SourceSuperWrapperA
    end
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "/tmp/source_applied_super_mro.cr"},
  )
  converter.no_prelude = true
  modules = [] of Adamas::Compiler::Frontend::ModuleNode
  classes = [] of Adamas::Compiler::Frontend::ClassNode
  program.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
      modules << node
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
      classes << node
    end
  end
  classes.each { |node| converter.lower_class(node) }
  modules.each { |node| converter.lower_module(node) }
  converter
end

describe "source-applied super MRO" do
  it "selects the next exact source Def and arena after the current applied module" do
    converter = source_applied_super_mro_converter
    converter.__test_source_super_successor(
      "SourceSuperHostAB",
      "SourceSuperOrigin",
      {"T" => "Int32"},
      "marker",
    ).should eq({"SourceSuperTailB", "SourceSuperTailB", true, "/tmp/source_applied_super_mro.cr"})

    converter = source_applied_super_mro_converter
    converter.__test_source_super_successor(
      "SourceSuperHostBA",
      "SourceSuperOrigin",
      {"T" => "Int32"},
      "marker",
    ).should eq({"SourceSuperTailA", "SourceSuperTailA", true, "/tmp/source_applied_super_mro.cr"})
  end

  it "does not guess a current module application when its generic binding is unresolved" do
    converter = source_applied_super_mro_converter
    converter.__test_source_super_successor(
      "SourceSuperHostAB",
      "SourceSuperOrigin",
      {"T" => "T"},
      "marker",
    ).should eq({nil, nil, false, nil})
  end
end
