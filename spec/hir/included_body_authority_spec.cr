require "../spec_helper"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_included_body_origin(owner : String, source_def : Adamas::Compiler::Frontend::DefNode,
                                  source_arena : Adamas::Compiler::Frontend::ArenaLike)
    origin = find_included_module_def_origin_for_owner(
      owner,
      "marker",
      1,
      false,
      compatible_arg_types: [TypeRef::INT32],
    )
    {
      origin.try { |entry| entry[2] },
      origin.try { |entry| entry[3] },
      origin.try { |entry| entry[0].same?(source_def) } || false,
      origin.try { |entry| entry[1].object_id == source_arena.object_id } || false,
    }
  end

  def __test_included_body_materialization(owner : String)
    target = mangle_function_name("#{owner}#marker", [TypeRef::INT32], false)
    registered_def = @function_defs[target]?
    registered_arena = @function_def_arenas[target]?
    function = @module.function_by_name(target)
    returned_literals = function.try do |body|
      values = {} of UInt32 => Adamas::HIR::Value
      body.blocks.each do |block|
        block.instructions.each { |instruction| values[instruction.id] = instruction }
      end
      body.blocks.compact_map do |block|
        terminator = block.terminator.as?(Adamas::HIR::Return) || next
        terminator.value.try { |value_id| values[value_id].as?(Adamas::HIR::Literal) }.try(&.int_value)
      end
    end || [] of Int64
    {
      target,
      registered_def,
      registered_arena,
      returned_literals,
      function_namespace_override_for(target),
      function_type_param_map_for_name(target).try(&.dup),
    }
  end
end

private def included_body_authority_converter
  source = <<-CRYSTAL
    module IncludedBodyTailA
      def marker(value : Int32) : Int32
        65
      end
    end
    module IncludedBodyTailB
      def marker(value : Int32) : Int32
        66
      end
    end
    module IncludedBodyWrapperA
      include IncludedBodyTailA
    end
    module IncludedBodyWrapperB
      include IncludedBodyTailB
    end
    module IncludedBodyRepeated(T)
      def marker(value : Int32) : Int32
        value
      end
    end
    module IncludedBodyRepeatedWrapper32
      include IncludedBodyRepeated(Int32)
    end
    module IncludedBodyRepeatedWrapper64
      include IncludedBodyRepeated(Int64)
    end
    class IncludedBodyHostAB
      include IncludedBodyWrapperA
      include IncludedBodyWrapperB
    end
    class IncludedBodyHostBA
      include IncludedBodyWrapperB
      include IncludedBodyWrapperA
    end
    class IncludedBodyHostDirect
      include IncludedBodyWrapperA
      include IncludedBodyWrapperB
      def marker(value : Int32) : Int32
        67
      end
    end
    class IncludedBodyRepeatedHostAB
      include IncludedBodyRepeatedWrapper32
      include IncludedBodyRepeatedWrapper64
    end
    class IncludedBodyRepeatedHostBA
      include IncludedBodyRepeatedWrapper64
      include IncludedBodyRepeatedWrapper32
    end
    IncludedBodyHostAB.new.marker(0)
    IncludedBodyHostBA.new.marker(0)
    IncludedBodyHostDirect.new.marker(0)
    IncludedBodyRepeatedHostAB.new.marker(0)
    IncludedBodyRepeatedHostBA.new.marker(0)
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "/tmp/included_body_authority.cr"},
  )
  converter.no_prelude = true
  modules = [] of Adamas::Compiler::Frontend::ModuleNode
  classes = [] of Adamas::Compiler::Frontend::ClassNode
  main = [] of UInt64
  tail_defs = {} of String => Adamas::Compiler::Frontend::DefNode
  direct_def = nil.as(Adamas::Compiler::Frontend::DefNode?)
  program.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::ModuleNode
      modules << node
      converter.register_module(node)
      name = String.new(node.name)
      if name == "IncludedBodyTailA" || name == "IncludedBodyTailB" || name == "IncludedBodyRepeated"
        node.body.not_nil!.each do |member_id|
          if definition = arena[member_id].as?(Adamas::Compiler::Frontend::DefNode)
            if String.new(definition.name) == "marker"
              tail_defs[name] = definition
            end
          end
        end
      end
    when Adamas::Compiler::Frontend::ClassNode
      classes << node
      converter.register_class(node)
      if String.new(node.name) == "IncludedBodyHostDirect"
        node.body.not_nil!.each do |member_id|
          if definition = arena[member_id].as?(Adamas::Compiler::Frontend::DefNode)
            direct_def = definition if String.new(definition.name) == "marker"
          end
        end
      end
    else
      main << root_id.index.to_u64
    end
  end
  classes.each { |node| converter.lower_class(node) }
  modules.each { |node| converter.lower_module(node) }
  converter.lower_main(main)
  converter.flush_pending_functions
  {converter, tail_defs, direct_def, arena}
end

describe "source MRO owns the actual included method body" do
  it "materializes the latest nested source Def for both include orders" do
    converter, tail_defs, direct_def, arena = included_body_authority_converter
    tail_a = tail_defs["IncludedBodyTailA"]
    tail_b = tail_defs["IncludedBodyTailB"]

    ab_origin = converter.__test_included_body_origin("IncludedBodyHostAB", tail_b, arena)
    ab_origin.should eq({"IncludedBodyTailB", "IncludedBodyTailB", true, true})
    ab_materialized = converter.__test_included_body_materialization("IncludedBodyHostAB")
    ab_materialized[1].should be(tail_b)
    ab_materialized[2].should be(arena)
    ab_materialized[3].should eq([66_i64])
    ab_materialized[4].should eq("IncludedBodyTailB")
    ab_materialized[5].should be_nil

    ba_origin = converter.__test_included_body_origin("IncludedBodyHostBA", tail_a, arena)
    ba_origin.should eq({"IncludedBodyTailA", "IncludedBodyTailA", true, true})
    ba_materialized = converter.__test_included_body_materialization("IncludedBodyHostBA")
    ba_materialized[1].should be(tail_a)
    ba_materialized[2].should be(arena)
    ba_materialized[3].should eq([65_i64])
    ba_materialized[4].should eq("IncludedBodyTailA")
    ba_materialized[5].should be_nil

    direct_materialized = converter.__test_included_body_materialization("IncludedBodyHostDirect")
    direct_materialized[1].should be(direct_def.not_nil!)
    direct_materialized[2].should be(arena)
    direct_materialized[3].should eq([67_i64])
    direct_materialized[4].should be_nil

    repeated_def = tail_defs["IncludedBodyRepeated"]
    repeated_ab_origin = converter.__test_included_body_origin("IncludedBodyRepeatedHostAB", repeated_def, arena)
    repeated_ab_origin.should eq({"IncludedBodyRepeated", "IncludedBodyRepeated(Int64)", true, true})
    repeated_ab = converter.__test_included_body_materialization("IncludedBodyRepeatedHostAB")
    repeated_ab[1].should be(repeated_def)
    repeated_ab[2].should be(arena)
    repeated_ab[4].should eq("IncludedBodyRepeated")
    repeated_ab[5].should eq({"T" => "Int64"})

    repeated_ba_origin = converter.__test_included_body_origin("IncludedBodyRepeatedHostBA", repeated_def, arena)
    repeated_ba_origin.should eq({"IncludedBodyRepeated", "IncludedBodyRepeated(Int32)", true, true})
    repeated_ba = converter.__test_included_body_materialization("IncludedBodyRepeatedHostBA")
    repeated_ba[1].should be(repeated_def)
    repeated_ba[2].should be(arena)
    repeated_ba[4].should eq("IncludedBodyRepeated")
    repeated_ba[5].should eq({"T" => "Int32"})
  end
end
