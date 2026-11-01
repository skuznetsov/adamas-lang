require "../spec_helper"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_mro_source_query_before_binding(receiver : String, analysis : Bool)
    type_ref_for_name(receiver)
    input = CallResolutionInput.new("#{receiver}#marker", 0, [] of TypeRef, true, false, false, nil)
    functions_before = @module.functions.size
    pending_before = @pending_function_queue.size
    selected = analysis ? resolve_call_target_for_analysis(input) : resolve_call_target(input)
    origin = find_included_module_def_origin_for_owner(
      receiver, "marker", 0, true,
      respect_direct_declarations: false, compatible_arg_types: [] of TypeRef,
    )
    {
      selected.try { |target| function_namespace_override_for(target.symbol_name) },
      selected.try { |target| origin.try { |found| target.def_node.same?(found[0]) } },
      selected.try { |target| origin.try { |found| target.source_arena.try(&.same?(found[1])) } },
      @module.functions.size == functions_before,
      @pending_function_queue.size == pending_before,
    }
  end

  def __test_named_mro_source_query_before_binding(receiver : String, label : String, analysis : Bool)
    type_ref_for_name(receiver)
    type = type_ref_for_name("Int32")
    input = CallResolutionInput.new(
      func_name: "#{receiver}#marker",
      arg_count: 1,
      arg_types: [type],
      has_block: true,
      has_splat: false,
      has_named: true,
      named_names: [label],
      raw_positional_count: 0,
      source_named_types: true,
    )
    raw = resolve_call_tuple(input)
    functions_before = @module.functions.size
    pending_before = @pending_function_queue.size
    selected = analysis ? resolve_call_target_for_analysis(input) : resolve_call_target(input)
    origin = find_included_module_def_origin_for_owner(
      receiver, "marker", 1, true,
      respect_direct_declarations: false,
      compatible_arg_types: [type],
      selection_input: input,
    )
    {
      raw.nil?,
      raw.try { |target| parse_method_name_compact(target[0]).owner },
      selected.try { |target| function_namespace_override_for(target.symbol_name) },
      selected.try { |target| origin.try { |found| target.def_node.same?(found[0]) } },
      selected.try { |target| origin.try { |found| target.source_arena.try(&.same?(found[1])) } },
      selected.try { |target| call_target_matches_call_shape?(input, target.def_node) },
      @module.functions.size == functions_before,
      @pending_function_queue.size == pending_before,
    }
  end

  def __test_named_mro_materialize_then_query(receiver : String, first_label : String, second_label : String)
    type_ref_for_name(receiver)
    type = type_ref_for_name("Int32")
    make_input = ->(label : String) do
      CallResolutionInput.new(
        func_name: "#{receiver}#marker",
        arg_count: 1,
        arg_types: [type],
        has_block: true,
        has_splat: false,
        has_named: true,
        named_names: [label],
        raw_positional_count: 0,
        source_named_types: true,
        )
    end
    first_input = make_input.call(first_label)
    first = resolve_call_target(first_input) || raise "missing first named MRO target"
    first_name = first.symbol_name
    lower_function_if_needed(first_name)
    first_body_after_lowering = @module.has_function_with_body?(first_name)

    second_input = make_input.call(second_label)
    second = resolve_call_target(second_input) || raise "missing second named MRO target"
    first_entry_preserved = @function_defs[first_name]?.try do |definition|
      same_def_node?(definition, first.def_node)
    end
    first_arena_preserved = @function_def_arenas[first_name]?.try do |arena|
      first.source_arena.try { |source_arena| arena.object_id == source_arena.object_id } || false
    end
    {
      first_name,
      second.symbol_name,
      function_namespace_override_for(first_name),
      function_namespace_override_for(second.symbol_name),
      call_target_matches_call_shape?(first_input, first.def_node),
      call_target_matches_call_shape?(second_input, second.def_node),
      first_body_after_lowering,
      @module.has_function_with_body?(first_name),
      first_entry_preserved,
      first_arena_preserved,
    }
  end

  def __test_named_mro_call_body_values : Array(Tuple(String, Int64?))
    main = @module.function_by_name("__adamas_main") || raise "missing lowered main"
    calls = main.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
      .select { |call| call.method_name.includes?("#marker") }
    calls.map do |call|
      function = @module.function_by_name(call.method_name)
      returned = nil.as(Int64?)
      if function
        function.blocks.each do |block|
          next unless terminator = block.terminator.as?(Adamas::HIR::Return)
          next unless value_id = terminator.value
          value = function.blocks.flat_map(&.instructions).find { |instruction| instruction.id == value_id }
          returned = value.try(&.as?(Adamas::HIR::Literal)).try(&.int_value)
        end
      end
      {call.method_name, returned}
    end
  end
end

private def source_applied_include_named_call_converter(calls : String) : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    module TupleOldLabel(E)
      def marker(old_value ignored : Int32, & : E ->) : Int32
        65
      end
    end
    module TupleNewLabel(E)
      def marker(new_value ignored : Int32, & : E ->) : Int32
        66
      end
    end
    struct Tuple
      include TupleOldLabel(Union(*T))
      include TupleNewLabel(Union(*T))
    end
    #{calls}
    CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "/tmp/source_applied_include_named_call.cr"})
  converter.no_prelude = true
  converter.arena = arena

  classes = [] of Adamas::Compiler::Frontend::ClassNode
  modules = [] of Adamas::Compiler::Frontend::ModuleNode
  main = [] of UInt64
  program.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
      classes << node
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
      modules << node
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

private def source_applied_include_binding_converter
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
    module NamedPriorBinding(E)
      def marker(code : Int32 = 65, & : E ->) : Int32
        code
      end
    end
    module NamedLastBinding(E)
      def marker(current : Int32 = 66, & : E ->) : Int32
        current
      end
    end
    struct Tuple
      include TuplePrior(Union(*T))
      include TupleLast(Union(*T))
    end
    struct NamedTupleProbe(T)
      include NamedPriorBinding(T)
      include NamedLastBinding(T)
    end
    class MroChild
      include TuplePrior(Int32)
      include TupleLast(Int32)
    end
    module OldLabelBinding(E)
      def marker(old_value ignored : Int32, & : E ->) : Int32
        65
      end
    end
    module NewLabelBinding(E)
      def marker(new_value ignored : Int32, & : E ->) : Int32
        66
      end
    end
    class NamedOlderChild
      include OldLabelBinding(Int32)
      include NewLabelBinding(Int32)
    end
    class NamedDirectChild
      include NamedPriorBinding(Int32)
      include NamedLastBinding(Int32)
      def marker(current : Int32 = 67, & : Int32 ->) : Int32
        67
      end
    end
    CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "/tmp/source_applied_include_binding.cr"})
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

describe "source included method selection before argument binding" do
  it "uses the exact Tuple MRO winner in the ordinary argument-binding query" do
    result = source_applied_include_binding_converter.__test_mro_source_query_before_binding("Tuple(Int32, Int64)", false)
    result[0].should eq("TupleLast")
    result[1].should be_true
    result[2].should be_true
  end

  it "uses the same source declaration in analysis without materializing bodies" do
    result = source_applied_include_binding_converter.__test_mro_source_query_before_binding("Tuple(Int32, Int64)", true)
    result[0].should eq("TupleLast")
    result[1].should be_true
    result[2].should be_true
    result[3].should be_true
    result[4].should be_true
  end

  it "settles included MRO for a nongeneric source class" do
    result = source_applied_include_binding_converter.__test_mro_source_query_before_binding("MroChild", false)
    result[0].should eq("TupleLast")
    result[1].should be_true
    result[2].should be_true
  end

  it "uses the latest included definition for its matching named label" do
    result = source_applied_include_binding_converter.__test_named_mro_source_query_before_binding(
      "NamedTupleProbe(Int32)", "current", false,
    )
    result[2].should eq("NamedLastBinding")
    result[3].should be_true
    result[4].should be_true
    result[5].should be_true
  end

  it "keeps an older included definition whose label the newer definition rejects" do
    result = source_applied_include_binding_converter.__test_named_mro_source_query_before_binding(
      "NamedOlderChild", "old_value", false,
    )
    result[2].should eq("OldLabelBinding")
    result[3].should be_true
    result[4].should be_true
    result[5].should be_true
  end

  it "resolves the older named label in analysis without materializing bodies" do
    result = source_applied_include_binding_converter.__test_named_mro_source_query_before_binding(
      "NamedOlderChild", "old_value", true,
    )
    result[2].should eq("OldLabelBinding")
    result[3].should be_true
    result[4].should be_true
    result[5].should be_true
    result[6].should be_true
    result[7].should be_true
  end

  it "keeps distinct included targets when the older label is queried after the newer body is lowered" do
    result = source_applied_include_binding_converter.__test_named_mro_materialize_then_query(
      "NamedOlderChild", "new_value", "old_value",
    )
    result[2].should eq("NewLabelBinding")
    result[3].should eq("OldLabelBinding")
    result[0].should_not eq(result[1])
    result[4].should be_true
    result[5].should be_true
    result[6].should be_true
    result[7].should be_true
    result[8].should be_true
    result[9].should be_true
  end

  it "keeps distinct included targets when the newer label is queried after the older body is lowered" do
    result = source_applied_include_binding_converter.__test_named_mro_materialize_then_query(
      "NamedOlderChild", "old_value", "new_value",
    )
    result[2].should eq("OldLabelBinding")
    result[3].should eq("NewLabelBinding")
    result[0].should_not eq(result[1])
    result[4].should be_true
    result[5].should be_true
    result[6].should be_true
    result[7].should be_true
    result[8].should be_true
    result[9].should be_true
  end

  it "keeps a compatible direct class declaration ahead of included modules" do
    result = source_applied_include_binding_converter.__test_named_mro_source_query_before_binding(
      "NamedDirectChild", "current", false,
    )
    result[2].should be_nil
    result[5].should be_true
  end

  it "keeps each selected source body through forward named block-call lowering" do
    converter = source_applied_include_named_call_converter(<<-CRYSTAL)
      {65, 66_i64}.marker(old_value: 1) { |value| }
      {65, 66_i64}.marker(new_value: 1) { |value| }
      CRYSTAL
    result = converter.__test_named_mro_call_body_values
    result.size.should eq(2)
    result.map(&.[1]).should eq([65_i64, 66_i64])
  end

  it "keeps each selected source body through reverse named block-call lowering" do
    converter = source_applied_include_named_call_converter(<<-CRYSTAL)
      {65, 66_i64}.marker(new_value: 1) { |value| }
      {65, 66_i64}.marker(old_value: 1) { |value| }
      CRYSTAL
    result = converter.__test_named_mro_call_body_values
    result.size.should eq(2)
    result.map(&.[1]).should eq([66_i64, 65_i64])
  end
end
