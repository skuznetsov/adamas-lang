require "../spec_helper"
require "../../src/compiler/semantic/diagnostic_formatter"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_initializer_source_functions : Array(Adamas::HIR::Function)
    @materialized_initializer_sources.values.map(&.function)
  end

  def __test_initializer_source_current?(name : String) : Bool
    materialized_initializer_source_current?(@materialized_initializer_sources[name])
  end

  def __test_initializer_origin_name(name : String) : String
    @materialized_initializer_sources[name].source_name
  end

  def __test_initializer_has_source_overload?(name : String) : Bool
    @function_defs.has_key?(name)
  end

  def __test_initializer_source_keys(name : String) : Tuple(String, String, String)
    source = @materialized_initializer_sources[name]
    {source.function.name, source.source_name, source.registered_base_name}
  end

  private def __test_clone_initializer_source(
    source : MaterializedInitializerSource,
    function : Adamas::HIR::Function,
    target_bindings : Hash(String, String)?,
    base_bindings : Hash(String, String)?,
  ) : MaterializedInitializerSource
    MaterializedInitializerSource.new(
      function, source.source_name, source.source_def, source.source_arena,
      source.namespace, source.bindings, source.registered_base_name,
      target_bindings.try(&.dup), base_bindings.try(&.dup),
      source.parameter_types, source.block_parameters, source.heap_block_param,
      source.callback_abi, source.callback_source, source.return_type,
      source.owner, source.owner_type, source.lowering_namespace,
      source.lowering_bindings, source.call_types, source.call_literals,
      source.call_enum_names, source.return_result_invalidated,
    )
  end

  def __test_initializer_replay_map_views(
    name : String,
    exact_bindings : Hash(String, String)?,
    base_bindings : Hash(String, String)?,
  ) : Tuple(Hash(String, String)?, Hash(String, String)?, Hash(String, String)?)
    original = @materialized_initializer_sources[name]
    # Exercise the production replay lookup with a captured recipe whose two
    # optional registry snapshots are explicit test inputs. Seeding the global
    # maps before lower_main is not a capture test: registration legitimately
    # rewrites those maps while lowering the source body.
    source = __test_clone_initializer_source(original, original.function, exact_bindings, base_bindings)
    previous = @active_initializer_replay_source
    @active_initializer_replay_source = source
    begin
      {
        function_type_param_map_for_name(source.function.name),
        function_type_param_map_for_name(source.registered_base_name),
        function_type_param_map_for(source.function.name, source.registered_base_name),
      }
    ensure
      @active_initializer_replay_source = previous
    end
  end

  def __test_record_initializer_callsite_hint(name : String, result : String) : Nil
    source = @materialized_initializer_sources[name]
    record_block_return_type_for_call("#{source.owner}.new$Nil_block", source.source_name, result)
  end

  def __test_record_exact_initializer_target_hint(name : String, result : String) : Nil
    source = @materialized_initializer_sources[name]
    record_block_return_type_for_call(source.function.name, source.registered_base_name, result)
  end

  def __test_initializer_has_callback_metadata?(name : String) : Bool
    source = @materialized_initializer_sources[name]
    !source.callback_abi.nil? || !source.callback_source.nil?
  end

  def __test_initializer_exact_target_has_block_hint?(name : String) : Bool
    source = @materialized_initializer_sources[name]
    function_type_param_map_for_name(source.function.name).try(&.has_key?("__block_return__")) || false
  end

  def __test_install_exact_target_probe(name : String) : String
    original = @materialized_initializer_sources[name]
    target_name = "#{original.function.name}$exact_target_probe"
    target = @module.create_function(target_name, original.return_type)
    source = __test_clone_initializer_source(
      original, target, original.registered_target_bindings, original.registered_base_bindings,
    )
    @materialized_initializer_sources[target_name] = source
    if bindings = source.registered_target_bindings
      @function_type_param_maps[target_name] = bindings.dup
    else
      @function_type_param_maps.delete(target_name)
    end
    target_name
  end

  def __test_initializer_source_definition_current?(name : String) : Bool
    initializer_source_definition_current?(@materialized_initializer_sources[name])
  end

  def __test_mutate_initializer_origin_binding(name : String, key : String, value : String) : Nil
    source = @materialized_initializer_sources[name]
    bindings = (function_type_param_map_for_name(source.source_name) || {} of String => String).dup
    bindings[key] = value
    @function_type_param_maps[source.source_name] = bindings
  end

  def __test_replay_initializer_origin(name : String) : Adamas::HIR::Function
    source = @materialized_initializer_sources[name]
    invalidate_lowered_layout_functions(source.owner)
    lower_function_if_needed(name)
    @module.function_by_name(name).not_nil!
  end

  def __test_forget_initializer_origin(name : String) : Nil
    source = @materialized_initializer_sources[name]
    @function_def_arenas.delete(source.source_name)
  end
end

private def lower_initializer_origin_fixture : Adamas::HIR::AstToHir
  code = <<-CRYSTAL
    class InitializerOrigin
      def initialize(value : Int, offset : Int32 = 3)
      end
    end
    InitializerOrigin.new(2)
  CRYSTAL
  result = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(code)
  ).parse_program
  converter = Adamas::HIR::AstToHir.new(result.arena)
  converter.arena = result.arena
  main = [] of UInt64
  result.roots.each do |id|
    case node = result.arena[id]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
      converter.lower_class(node)
    else
      main << id.index.to_u64
    end
  end
  converter.lower_main(main)
  converter.flush_pending_functions
  converter.refresh_void_type_params
  converter.flush_deferred_allocators
  converter.__test_initializer_source_functions.should_not be_empty
  converter
end

describe "materialized initializer source identity" do
  it "retains the registered source identity of a completed initializer" do
    converter = lower_initializer_origin_fixture
    function = converter.__test_initializer_source_functions.first
    source_name = converter.__test_initializer_origin_name(function.name)
    converter.__test_initializer_has_source_overload?(source_name).should be_true
    converter.__test_initializer_source_current?(function.name).should be_true
  end

  it "keeps captured exact and base registration maps separate and prefers exact" do
    converter = lower_initializer_origin_fixture
    function = converter.__test_initializer_source_functions.first
    views = converter.__test_initializer_replay_map_views(
      function.name,
      {"exact_probe" => "Int32", "precedence_probe" => "Exact"},
      {"base_probe" => "Bool", "precedence_probe" => "Base"},
    )
    views[0].try(&.["exact_probe"]?).should eq("Int32")
    views[0].try(&.["base_probe"]?).should be_nil
    views[1].try(&.["base_probe"]?).should eq("Bool")
    views[1].try(&.["exact_probe"]?).should be_nil
    views[2].try(&.["exact_probe"]?).should eq("Int32")
    views[2].try(&.["base_probe"]?).should be_nil
    views[2].try(&.["precedence_probe"]?).should eq("Exact")
  end

  it "preserves absent exact-map presence while pair lookup falls back to base" do
    converter = lower_initializer_origin_fixture
    function = converter.__test_initializer_source_functions.first
    views = converter.__test_initializer_replay_map_views(function.name, nil, {"base_probe" => "Bool"})
    views[0].should be_nil
    views[1].try(&.["base_probe"]?).should eq("Bool")
    views[2].try(&.["base_probe"]?).should eq("Bool")

    absent = converter.__test_initializer_replay_map_views(function.name, nil, nil)
    absent[0].should be_nil
    absent[1].should be_nil
    absent[2].should be_nil
  end

  it "keeps a foreign constructor block result out of declaration identity" do
    converter = lower_initializer_origin_fixture
    function = converter.__test_initializer_source_functions.first
    function.params.any?(&.is_block).should be_false
    converter.__test_initializer_source_current?(function.name).should be_true
    converter.__test_record_initializer_callsite_hint(function.name, "Nil")
    converter.__test_initializer_source_current?(function.name).should be_true
    converter.__test_record_initializer_callsite_hint(function.name, "Int32")
    converter.__test_initializer_source_current?(function.name).should be_true
  end

  it "replays the same blockless source and ABI after a foreign block hint" do
    converter = lower_initializer_origin_fixture
    function = converter.__test_initializer_source_functions.first
    converter.__test_record_initializer_callsite_hint(function.name, "Nil")
    replayed = converter.__test_replay_initializer_origin(function.name)
    replayed.should_not be(function)
    replayed.params.map(&.type).should eq(function.params.map(&.type))
    replayed.params.map(&.is_block).should eq(function.params.map(&.is_block))
    replayed.return_type.should eq(function.return_type)
    converter.__test_initializer_source_current?(replayed.name).should be_true
  end

  it "rejects a changed exact-target block hint without callback metadata" do
    converter = lower_initializer_origin_fixture
    function = converter.__test_initializer_source_functions.first
    target_name = converter.__test_install_exact_target_probe(function.name)
    keys = converter.__test_initializer_source_keys(target_name)
    target_name.should_not eq(keys[1])
    target_name.should_not eq(keys[2])
    converter.__test_initializer_has_callback_metadata?(function.name).should be_false
    converter.__test_initializer_source_definition_current?(target_name).should be_true

    converter.__test_record_exact_initializer_target_hint(target_name, "Bool")

    converter.__test_initializer_exact_target_has_block_hint?(target_name).should be_true
    converter.__test_initializer_has_callback_metadata?(target_name).should be_false
    converter.__test_initializer_source_definition_current?(target_name).should be_false
  end

  it "still rejects changed generic bindings after a foreign block hint" do
    converter = lower_initializer_origin_fixture
    function = converter.__test_initializer_source_functions.first
    converter.__test_record_initializer_callsite_hint(function.name, "Nil")
    converter.__test_mutate_initializer_origin_binding(function.name, "T", "Bool")
    converter.__test_initializer_source_current?(function.name).should be_false
  end

  it "does not discard other reserved ABI keys from source identity" do
    converter = lower_initializer_origin_fixture
    function = converter.__test_initializer_source_functions.first
    converter.__test_mutate_initializer_origin_binding(function.name, "__yield_call_abi__", "Int32")
    converter.__test_initializer_source_current?(function.name).should be_false
  end

  it "rejects an initializer whose return ABI changes after lowering" do
    converter = lower_initializer_origin_fixture
    function = converter.__test_initializer_source_functions.first
    converter.__test_initializer_source_current?(function.name).should be_true
    function.return_type = Adamas::HIR::TypeRef::INT64
    converter.__test_initializer_source_current?(function.name).should be_false
  end

  it "rejects an initializer whose source arena is no longer registered" do
    converter = lower_initializer_origin_fixture
    function = converter.__test_initializer_source_functions.first
    converter.__test_initializer_source_current?(function.name).should be_true
    converter.__test_forget_initializer_origin(function.name)
    converter.__test_initializer_source_current?(function.name).should be_false
  end
end
