require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_invalidate_initializer_layout(owner : String) : Nil
    # Model a later layout update after the ordinary pending pass has
    # consumed constructor callsites through its production API.
    @pending_arg_types.keys.each do |name|
      pop_pending_callsite_args(name, name) if name.starts_with?("#{owner}#initialize")
    end
    # Allocator-emitted calls can have a complete body when missing-demand
    # discovery runs and therefore have no separate RTA demand to replay.
    @module.functions.each do |function|
      @rta_called_methods.delete(function.name) if function.name.starts_with?("#{owner}#initialize")
    end
    invalidate_lowered_layout_functions(owner)
  end

  def __test_initializer_replay_body(name : String) : Adamas::HIR::Function?
    @module.function_by_name(name) if @module.has_function_with_body?(name)
  end

  def __test_replay_exact_initializer(name : String) : Nil
    lower_function_if_needed(name)
  end

  def __test_replay_initializer_from_nested_allocator(name : String) : Nil
    @lowering_depth += 1
    begin
      # The nested-demand path queues first. The allocator's immediate
      # fallback must then consume the same source recipe, not reselect.
      lower_function_if_needed(name)
      rematerialize_missing_function_body(name) do
        raise "allocator fallback tried to reselect a materialized initializer"
      end
    ensure
      @lowering_depth -= 1
    end
  end

  def __test_initializer_replay_pending?(name : String) : Bool
    function_state(name).pending?
  end

  def __test_change_initializer_callback_abi(name : String) : Nil
    @raw_callback_abis[name] = RawCallbackAbi.new(
      [Adamas::HIR::TypeRef::INT32], Adamas::HIR::TypeRef::INT64, Adamas::HIR::TypeRef::POINTER,
    )
  end

  def __test_change_initializer_source(name : String, change : Symbol) : Nil
    source = @materialized_initializer_sources[name]
    case change
    when :def
      replacement = @function_defs.values.find { |node| !node.same?(source.source_def) }.not_nil!
      @function_defs[source.source_name] = replacement
    when :arena
      @function_def_arenas[source.source_name] = Adamas::Compiler::Frontend::Parser.new(
        Adamas::Compiler::Frontend::Lexer.new("1")
      ).parse_program.arena
    when :namespace
      store_function_namespace_override(source.source_name, source.source_name, "DifferentOwner", store_base: false)
    when :bindings
      store_function_type_param_map(source.source_name, source.source_name, {"T" => "Bool"}, store_base: false)
    end
  end

  def __test_replay_initializer_in_other_context(name : String) : Nil
    hostile = {"String" => "Int32", "T" => "Bool"}
    with_isolated_type_param_map(hostile) do
      with_namespace_override("DifferentOwner") do
        lower_function_if_needed(name)
        @type_param_map.should eq(hostile)
        @current_namespace_override.should eq("DifferentOwner")
      end
    end
  end
end

private def lower_initializer_replay_fixture(block_form : Symbol = :captured) : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    class ReplayBox
      @name : String?
      @run : ->

      def initialize(@name : String? = nil, &@run : ->)
        @code = 17
      end

      def initialize
        @name = nil
        @run = -> {}
        @code = 39
      end
    end
    ReplayBox.new("name") {}
  CRYSTAL
  if block_form == :raw
    source = source.sub("&@run : ->", "&block")
      .sub("@run : ->", "")
      .sub("@run = -> {}", "")
      .sub("@code = 17", "@code = 17\nyield")
  elsif block_form == :heap
    source = source.sub("&@run : ->", "&block : ->")
      .sub("@code = 17", "@run = block\n@code = 17")
  end
  parsed = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source)
  ).parse_program
  converter = Adamas::HIR::AstToHir.new(parsed.arena)
  main = [] of UInt64
  parsed.roots.each do |id|
    if (node = parsed.arena[id]).is_a?(Adamas::Compiler::Frontend::ClassNode)
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
  converter
end

describe "selected initializer replay after layout invalidation" do
  it "consumes the selected recipe before a nested allocator fallback" do
    converter = lower_initializer_replay_fixture
    name = "ReplayBox#initialize$String_block"
    converter.__test_invalidate_initializer_layout("ReplayBox")
    converter.__test_replay_initializer_from_nested_allocator(name)
    converter.__test_initializer_replay_body(name).should_not be_nil
  end

  it "rebuilds the exact concrete block initializer without an RTA entry" do
    converter = lower_initializer_replay_fixture
    name = "ReplayBox#initialize$String_block"
    before = converter.__test_initializer_replay_body(name)
    before.should_not be_nil
    parameter_types = before.not_nil!.params.map(&.type)
    heap_block_param = before.not_nil!.heap_block_param

    converter.__test_invalidate_initializer_layout("ReplayBox")
    converter.__test_initializer_replay_body(name).should be_nil
    converter.__test_initializer_replay_pending?(name).should be_true
    # Replay the missing callee before any allocator wrapper happens to run.
    # A wrapper's later re-selection must not be required to restore identity.
    converter.__test_replay_exact_initializer(name)

    after = converter.__test_initializer_replay_body(name)
    after.should_not be_nil
    after.not_nil!.should_not be(before.not_nil!)
    after.not_nil!.params.map(&.type).should eq(parameter_types)
    after.not_nil!.heap_block_param.should eq(heap_block_param)
    after.not_nil!.blocks.flat_map(&.instructions).any? do |instruction|
      instruction.is_a?(Adamas::HIR::Literal) && instruction.value == 17_i64
    end.should be_true
  end

  it "replays an explicitly captured heap Proc without changing its carrier" do
    converter = lower_initializer_replay_fixture(:heap)
    name = "ReplayBox#initialize$String_block"
    before = converter.__test_initializer_replay_body(name).not_nil!
    before.heap_block_param.should be_true
    before.params.any?(&.is_block).should be_true
    converter.__test_invalidate_initializer_layout("ReplayBox")
    converter.__test_replay_exact_initializer(name)
    after = converter.__test_initializer_replay_body(name).not_nil!
    after.params.map(&.type).should eq(before.params.map(&.type))
    after.params.map(&.is_block).should eq(before.params.map(&.is_block))
    after.heap_block_param.should be_true
  end

  it "replays a raw yielding block without changing its carrier" do
    converter = lower_initializer_replay_fixture(:raw)
    name = "ReplayBox#initialize$String_block"
    before = converter.__test_initializer_replay_body(name).not_nil!
    before.heap_block_param.should be_false
    before.params.any?(&.is_block).should be_true
    converter.__test_invalidate_initializer_layout("ReplayBox")
    converter.__test_replay_exact_initializer(name)
    after = converter.__test_initializer_replay_body(name).not_nil!
    after.params.map(&.type).should eq(before.params.map(&.type))
    after.params.map(&.is_block).should eq(before.params.map(&.is_block))
    after.heap_block_param.should eq(before.heap_block_param)
  end

  it "rejects a new callback ABI instead of changing the saved block carrier" do
    converter = lower_initializer_replay_fixture
    name = "ReplayBox#initialize$String_block"
    converter.__test_invalidate_initializer_layout("ReplayBox")
    converter.__test_change_initializer_callback_abi(name)
    expect_raises(Adamas::HIR::LoweringError, /initializer replay callback ABI changed/) do
      converter.__test_replay_exact_initializer(name)
    end
    converter.__test_initializer_replay_body(name).should be_nil
  end

  it "isolates the saved call context from the replay caller" do
    converter = lower_initializer_replay_fixture
    name = "ReplayBox#initialize$String_block"
    before = converter.__test_initializer_replay_body(name).not_nil!
    converter.__test_invalidate_initializer_layout("ReplayBox")
    converter.__test_replay_initializer_in_other_context(name)
    after = converter.__test_initializer_replay_body(name).not_nil!
    after.params.map(&.type).should eq(before.params.map(&.type))
    after.params.map(&.is_block).should eq(before.params.map(&.is_block))
  end

  [:def, :arena, :namespace, :bindings].each do |change|
    it "rejects changed #{change} source evidence instead of reselecting a constructor" do
      converter = lower_initializer_replay_fixture
      name = "ReplayBox#initialize$String_block"
      converter.__test_invalidate_initializer_layout("ReplayBox")
      converter.__test_change_initializer_source(name, change)
      expect_raises(Adamas::HIR::LoweringError, /initializer replay source changed/) do
        converter.__test_replay_exact_initializer(name)
      end
      converter.__test_initializer_replay_body(name).should be_nil
    end
  end
end
