require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_lower_method_super_source(
    definition : Adamas::Compiler::Frontend::DefNode,
    source_arena : Adamas::Compiler::Frontend::ArenaLike,
    ambient : String,
    provider : String? = nil,
  ) : {Function, String?}
    name = "MethodSuperBox#value"
    saved = @current_super_source_module
    begin
      @current_super_source_module = ambient
      set_function_def_entry(name, definition, false)
      set_function_def_arena(name, source_arena)
      remember_callsite_arg_types(name, ([] of TypeRef), nil, nil, false)
      with_arena(source_arena) do
        lower_method("MethodSuperBox", @class_info["MethodSuperBox"], definition,
          full_name_override: name, super_source_module: provider)
      end
      {@module.function_by_name(name).not_nil!, @current_super_source_module}
    ensure
      @current_super_source_module = saved
    end
  end

  def __test_retire_method_super_source : Function
    name = "MethodSuperBox#value"
    previous = @module.function_by_name(name).not_nil!
    remember_callsite_arg_types(name, ([] of TypeRef), nil, nil, false)
    remove_hir_function(name)
    clear_function_state(name)
    clear_function_type_entry(name)
    previous
  end

  def __test_force_method_super_source(ambient : String) : {Bool, Function, String?}
    saved = @current_super_source_module
    begin
      @current_super_source_module = ambient
      progress = force_lower_function_for_return_type("MethodSuperBox#value")
      {progress, @module.function_by_name("MethodSuperBox#value").not_nil!, @current_super_source_module}
    ensure
      @current_super_source_module = saved
    end
  end

  def __test_method_super_source_recipe?(
    function : Function,
    definition : Adamas::Compiler::Frontend::DefNode,
    source_arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Bool
    @module.function_by_name(function.name).try(&.same?(function)) == true &&
      @function_defs[function.name]?.try(&.same?(definition)) == true &&
      @function_def_arenas[function.name]?.try(&.same?(source_arena)) == true
  end
end

private def method_super_source_fixture
  source = <<-CRYSTAL
    module MethodSuperLeaf
      def value : Int32
        65
      end
    end

    module MethodSuperBridge
      include MethodSuperLeaf

      def value : Int32
        super
      end
    end

    class MethodSuperBox
      include MethodSuperBridge
    end
  CRYSTAL
  # A reopening supplies a genuinely different Def and arena for the same
  # physical method. Its super must start at Bridge, rather than above it.
  reopening_source = <<-CRYSTAL
    class MethodSuperBox
      def value : Int32
        super
      end
    end
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  reopening_parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(reopening_source))
  reopening = reopening_parser.parse_program
  reopening_parser.diagnostics.should be_empty
  arena = program.arena
  reopening_arena = reopening.arena
  converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {
    arena.object_id.to_u64 => source,
    reopening_arena.object_id.to_u64 => reopening_source,
  })
  converter.no_prelude = true
  converter.seed_top_level_type_names(["MethodSuperLeaf", "MethodSuperBridge", "MethodSuperBox"])
  converter.seed_top_level_class_kinds([{"MethodSuperBox", false}])
  modules = [] of Adamas::Compiler::Frontend::ModuleNode
  program.roots.each do |id|
    case node = arena[id]
    when Adamas::Compiler::Frontend::ModuleNode
      modules << node
      converter.register_module(node)
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    end
  end
  middle = modules.last.body.not_nil!.compact_map do |id|
    arena[id].as?(Adamas::Compiler::Frontend::DefNode)
  end.first
  reopened_owner = reopening_arena[reopening.roots.first].as(Adamas::Compiler::Frontend::ClassNode)
  ordinary = reopened_owner.body.not_nil!.compact_map do |id|
    reopening_arena[id].as?(Adamas::Compiler::Frontend::DefNode)
  end.first
  {converter, middle, arena, ordinary, reopening_arena}
end

private def method_super_source_calls(function : Adamas::HIR::Function) : Array(Adamas::HIR::Call)
  function.blocks.flat_map(&.instructions).select(Adamas::HIR::Call)
end

private def expect_method_super_source_target(
  converter : Adamas::HIR::AstToHir,
  function : Adamas::HIR::Function,
  provider : String,
) : Nil
  target = "MethodSuperBox#value_super_from_#{provider}"
  calls = method_super_source_calls(function)
  calls.map(&.method_name).should eq([target])
  calls.first.type.should eq(Adamas::HIR::TypeRef::INT32)
  calls.first.receiver.should eq(function.params.first.id)
  function.return_type.should eq(Adamas::HIR::TypeRef::INT32)
  converter.module.function_by_name(target).should_not be_nil
end

describe "physical method super source ownership" do
  it "clears an ordinary body's inherited module marker and restores its caller" do
    converter, _, _, ordinary, arena = method_super_source_fixture
    function, restored = converter.__test_lower_method_super_source(ordinary, arena, "MethodSuperBridge")
    expect_method_super_source_target(converter, function, "MethodSuperBridge")
    converter.__test_method_super_source_recipe?(function, ordinary, arena).should be_true
    restored.should eq("MethodSuperBridge")
  end

  it "starts an explicit module body above its own exact provider" do
    converter, definition, arena, _, _ = method_super_source_fixture
    function, restored = converter.__test_lower_method_super_source(definition, arena, "CallerProvider", "MethodSuperBridge")
    expect_method_super_source_target(converter, function, "MethodSuperLeaf")
    converter.__test_method_super_source_recipe?(function, definition, arena).should be_true
    leaf = converter.module.function_by_name("MethodSuperBox#value_super_from_MethodSuperLeaf").not_nil!
    literals = leaf.blocks.flat_map(&.instructions).select(Adamas::HIR::Literal)
    literals.map(&.value).should contain(65_i64)
    restored.should eq("CallerProvider")
  end

  it "retains the selected module source across exact forced rematerialization" do
    converter, definition, arena, _, _ = method_super_source_fixture
    original, _ = converter.__test_lower_method_super_source(definition, arena, "CallerProvider", "MethodSuperBridge")
    converter.__test_retire_method_super_source.same?(original).should be_true
    progress, replayed, restored = converter.__test_force_method_super_source("MethodSuperLeaf")
    progress.should be_true
    replayed.same?(original).should be_false
    expect_method_super_source_target(converter, replayed, "MethodSuperLeaf")
    converter.__test_method_super_source_recipe?(replayed, definition, arena).should be_true
    restored.should eq("MethodSuperLeaf")
  end

  it "does not lend a retired provider to another Def and arena under the same symbol" do
    converter, definition, arena, ordinary, ordinary_arena = method_super_source_fixture
    original, _ = converter.__test_lower_method_super_source(definition, arena, "CallerProvider", "MethodSuperBridge")
    converter.__test_retire_method_super_source.same?(original).should be_true
    replacement, restored = converter.__test_lower_method_super_source(ordinary, ordinary_arena, "MethodSuperBridge")
    replacement.same?(original).should be_false
    expect_method_super_source_target(converter, replacement, "MethodSuperBridge")
    converter.__test_method_super_source_recipe?(replacement, ordinary, ordinary_arena).should be_true
    converter.__test_method_super_source_recipe?(replacement, definition, arena).should be_false
    restored.should eq("MethodSuperBridge")
  end
end
