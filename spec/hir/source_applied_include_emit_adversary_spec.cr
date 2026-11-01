require "../spec_helper"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_cross_arena_named_shape(receiver : String, label : String, block_return_name : String)
    int32 = type_ref_for_name("Int32")
    input = CallResolutionInput.new(
      func_name: "#{receiver}#marker",
      arg_count: 2,
      arg_types: [int32, int32],
      has_block: true,
      has_splat: false,
      has_named: true,
      named_names: [label],
      raw_positional_count: 1,
      source_named_types: true,
    )
    selected = resolve_call_target(input) || raise "missing named source target for #{label}"
    origin = find_included_module_def_origin_for_owner(
      receiver,
      "marker",
      input.arg_count,
      input.has_block,
      respect_direct_declarations: false,
      compatible_arg_types: input.arg_types,
      selection_input: input,
    ) || raise "missing named source origin for #{label}"
    shaped_name = shape_keyed_block_target(
      "#{receiver}#marker",
      input.arg_types || [] of Adamas::HIR::TypeRef,
      selected.def_node,
      selected.symbol_name,
      block_return_name,
      selected.source_arena,
    )
    specialization = @block_shape_specializations[shaped_name]?
    {
      selected.symbol_name,
      function_namespace_override_for(selected.symbol_name),
      selected.def_node.same?(origin[0]),
      selected.source_arena.try { |arena| source_path_for(arena) },
      shaped_name,
      specialization.try { |shape| shape.source_def.same?(selected.def_node) },
      specialization.try { |shape| selected.source_arena.try { |arena| shape.arena.object_id == arena.object_id } || false },
      specialization.try(&.block_return_name),
    }
  end

  def __test_mro_emit_call_records
    main = @module.function_by_name("__adamas_main") || raise "missing lowered main"
    main.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
      .select { |call| call.method_name.includes?("#marker") }
      .map do |call|
        function = @module.function_by_name(call.method_name)
        source_arena = @function_def_arenas[call.method_name]?
        {
          call.method_name,
          function_namespace_override_for(call.method_name),
          function.try(&.return_type),
          @function_defs.has_key?(call.method_name),
          source_arena.try { |arena| source_path_for(arena) },
        }
      end
  end

  def __test_nonblock_named_call_records
    main = @module.function_by_name("__adamas_main") || raise "missing lowered main"
    main.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
      .select { |call| call.method_name.includes?("#marker") }
      .map do |call|
        function = @module.function_by_name(call.method_name)
        returned = nil.as(Int64?)
        if function
          function.not_nil!.blocks.each do |block|
            next unless terminator = block.terminator.as?(Adamas::HIR::Return)
            next unless value_id = terminator.value
            value = function.not_nil!.blocks.flat_map(&.instructions).find { |instruction| instruction.id == value_id }
            returned = value.try(&.as?(Adamas::HIR::Literal)).try(&.int_value)
          end
        end
        {
          call.method_name,
          function_namespace_override_for(call.method_name),
          returned,
          @function_defs.has_key?(call.method_name),
        }
      end
  end

  def __test_direct_nonblock_named_target(receiver : String, label : String)
    int32 = type_ref_for_name("Int32")
    input = CallResolutionInput.new(
      func_name: "#{receiver}#direct_marker",
      arg_count: 1,
      arg_types: [int32],
      has_block: false,
      has_splat: false,
      has_named: true,
      named_names: [label],
      raw_positional_count: 0,
      source_named_types: true,
    )
    selected = resolve_call_target(input) || raise "missing direct named target"
    included = find_included_module_def_origin_for_owner(
      receiver,
      "direct_marker",
      input.arg_count,
      false,
      respect_direct_declarations: false,
      compatible_arg_types: input.arg_types,
      selection_input: input,
    ) || raise "missing included direct-name control"
    {
      selected.symbol_name,
      method_owner(selected.symbol_name),
      function_namespace_override_for(selected.symbol_name),
      selected.def_node.same?(included[0]),
      call_target_matches_call_shape?(input, selected.def_node),
    }
  end
end

private def source_applied_include_cross_arena_return_converter
  old_source = <<-CRYSTAL
    module TupleOldReturn(E)
      def marker(value : E, old_value ignored : Int32, & : E -> U) forall U
        result = yield value
        result
      end
    end
    CRYSTAL
  old_parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(old_source))
  old_program = old_parser.parse_program
  old_parser.diagnostics.should be_empty
  old_arena = old_program.arena
  old_module = old_program.roots.compact_map { |id| old_arena[id].as?(Adamas::Compiler::Frontend::ModuleNode) }.first || raise "missing old module"

  new_source = <<-CRYSTAL
    module TupleNewReturn(E)
      def marker(value : E, new_value ignored : Int32, & : E -> U) forall U
        result = yield value
        result
      end
    end
    CRYSTAL
  new_parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(new_source))
  new_program = new_parser.parse_program
  new_parser.diagnostics.should be_empty
  new_arena = new_program.arena
  new_module = new_program.roots.compact_map { |id| new_arena[id].as?(Adamas::Compiler::Frontend::ModuleNode) }.first || raise "missing new module"

  main_source = <<-CRYSTAL
    struct Tuple
      include TupleOldReturn(Union(*T))
      include TupleNewReturn(Union(*T))
    end
    {65, 66_i64}.marker(1, old_value: 1) { |value| 65 }
    {65, 66_i64}.marker(1, new_value: 1) { |value| 66_i64 }
    {65, 66_i64}.marker(1, old_value: 1) { |value| 67_i64 }
    {65, 66_i64}.marker(1, new_value: 1) { |value| 68 }
    {65, 66_i64}.marker(1, new_value: 1) { |value| 69_i64 }
    {65, 66_i64}.marker(1, old_value: 1) { |value| 70 }
    CRYSTAL
  main_parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(main_source))
  main_program = main_parser.parse_program
  main_parser.diagnostics.should be_empty
  main_arena = main_program.arena

  converter = Adamas::HIR::AstToHir.new(main_arena,
    sources_by_arena: {
      old_arena.object_id.to_u64  => old_source,
      new_arena.object_id.to_u64  => new_source,
      main_arena.object_id.to_u64 => main_source,
    },
    paths_by_arena: {
      old_arena.object_id.to_u64  => "/tmp/mro_emit_old_return.cr",
      new_arena.object_id.to_u64  => "/tmp/mro_emit_new_return.cr",
      main_arena.object_id.to_u64 => "/tmp/mro_emit_main_return.cr",
    })
  converter.no_prelude = true

  converter.arena = old_arena
  converter.register_module(old_module)
  converter.arena = new_arena
  converter.register_module(new_module)

  tuple_node = nil.as(Adamas::Compiler::Frontend::ClassNode?)
  main_roots = [] of UInt64
  main_program.roots.each do |root_id|
    case node = main_arena[root_id]
    when Adamas::Compiler::Frontend::ClassNode
      tuple_node = node
      converter.arena = main_arena
      converter.register_class(node)
    else
      main_roots << root_id.index.to_u64
    end
  end
  converter.arena = main_arena
  converter.lower_class(tuple_node || raise "missing Tuple class")
  converter.lower_main(main_roots)
  converter.flush_pending_functions
  converter
end

private def source_applied_include_nonblock_named_converter
  source = <<-CRYSTAL
    module TupleOldPlain(E)
      def marker(old_value ignored : Int32) : Int32
        71
      end
    end
    module TupleNewPlain(E)
      def marker(new_value ignored : Int32) : Int32
        72
      end
    end
    module TupleDirectPlain(E)
      def direct_marker(current ignored : Int32) : Int32
        73
      end
    end
    struct Tuple
      include TupleOldPlain(Union(*T))
      include TupleNewPlain(Union(*T))
    end
    class MroNamedDirect
      include TupleDirectPlain(Int32)
      def direct_marker(current ignored : Int32) : Int32
        74
      end
    end
    {1, 2_i64}.marker(old_value: 1)
    {1, 2_i64}.marker(new_value: 1)
    MroNamedDirect.new.direct_marker(current: 1)
    CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "/tmp/mro_emit_nonblock_named.cr"})
  converter.no_prelude = true

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

describe "source included MRO through emitted block shapes" do
  it "keeps named block-return shapes tied to their source arena across interleaving" do
    converter = source_applied_include_cross_arena_return_converter
    cases = [
      {"old_value", "Int32", "TupleOldReturn", "/tmp/mro_emit_old_return.cr"},
      {"new_value", "Int64", "TupleNewReturn", "/tmp/mro_emit_new_return.cr"},
      {"old_value", "Int64", "TupleOldReturn", "/tmp/mro_emit_old_return.cr"},
      {"new_value", "Int32", "TupleNewReturn", "/tmp/mro_emit_new_return.cr"},
      {"new_value", "Int64", "TupleNewReturn", "/tmp/mro_emit_new_return.cr"},
      {"old_value", "Int32", "TupleOldReturn", "/tmp/mro_emit_old_return.cr"},
    ] of Tuple(String, String, String, String)
    result = cases.map do |(label, return_name, owner, path)|
      selected = converter.__test_cross_arena_named_shape("Tuple(Int32, Int64)", label, return_name)
      selected[1].should eq(owner)
      selected[2].should be_true
      selected[3].should eq(path)
      selected[5].should be_true
      selected[6].should be_true
      selected[7].should eq(return_name)
      selected
    end
    result[0][4].should_not eq(result[1][4])
    result[0][4].should_not eq(result[2][4])
    result[1][4].should_not eq(result[3][4])
    result[0][4].should eq(result[5][4])
    result[1][4].should eq(result[4][4])
  end

  it "keeps named non-block twin overloads independently callable" do
    result = source_applied_include_nonblock_named_converter.__test_nonblock_named_call_records
    result.size.should eq(2)
    result.map(&.[2]).should eq([71_i64, 72_i64])
    result[0][1].should eq("TupleOldPlain")
    result[1][1].should eq("TupleNewPlain")
    result.each { |record| record[3].should be_true }
  end

  it "keeps a matching direct class named overload ahead of included modules" do
    result = source_applied_include_nonblock_named_converter.__test_direct_nonblock_named_target(
      "MroNamedDirect", "current",
    )
    result[1].should eq("MroNamedDirect")
    result[2].should be_nil
    result[3].should be_false
    result[4].should be_true
  end
end
