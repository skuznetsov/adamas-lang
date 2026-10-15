require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def block_carrier_parse(
  code : String,
) : {Adamas::Compiler::Frontend::ArenaLike, Hash(String, Adamas::Compiler::Frontend::DefNode)}
  lexer = Adamas::Compiler::Frontend::Lexer.new(code)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  defs = {} of String => Adamas::Compiler::Frontend::DefNode
  result.roots.each do |root|
    next unless root
    node = result.arena[root]
    next unless def_node = node.as?(Adamas::Compiler::Frontend::DefNode)
    next unless name = Adamas::Compiler::Frontend.node_def_name_string(def_node)
    defs[name] = def_node
  end
  {result.arena, defs}
end

class Adamas::HIR::AstToHir
  def __test_register_function_def(
    name : String,
    def_node : Adamas::Compiler::Frontend::DefNode,
    arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Nil
    register_function_def(name, def_node, arena)
  end

  def __test_block_arg_requires_heap_proc?(target_name : String, selected_def : Adamas::Compiler::Frontend::DefNode, selected_arena : Adamas::Compiler::Frontend::ArenaLike) : Bool
    block_arg_requires_heap_proc?(target_name, selected_def, selected_arena)
  end

  def __test_materialized_block_arg_requires_heap_proc?(
    target_name : String,
    selected_def : Adamas::Compiler::Frontend::DefNode,
    selected_arena : Adamas::Compiler::Frontend::ArenaLike,
    *,
    body_emitted : Bool,
    block_parameter : Bool,
    heap_block_parameter : Bool,
    contains_yield : Bool,
  ) : Bool
    function = @module.create_function(target_name, Adamas::HIR::TypeRef::VOID)
    function.add_param("block", Adamas::HIR::TypeRef::POINTER, is_block: true) if block_parameter
    function.heap_block_param = heap_block_parameter
    if body_emitted
      block = function.get_block(function.entry_block)
      if contains_yield
        block.add(Adamas::HIR::Yield.new(function.next_value_id, Adamas::HIR::TypeRef::VOID))
      end
      block.terminator = Adamas::HIR::Return.new
    end
    block_arg_requires_heap_proc?(target_name, selected_def, selected_arena)
  end
end

describe "selected block carrier" do
  it "uses only the selected raw-yield definition regardless of sibling order" do
    sources = [
      <<-CRYSTAL,
        def raw_yield(&block)
          yield
        end

        def stored_block(&block)
          block.call(1)
        end
        CRYSTAL
      <<-CRYSTAL,
        def stored_block(&block)
          block.call(1)
        end

        def raw_yield(&block)
          yield
        end
        CRYSTAL
    ]

    sources.each_with_index do |source, order|
      arena, defs = block_carrier_parse(source)
      converter = Adamas::HIR::AstToHir.new(arena)
      converter.arena = arena
      candidates = if order == 0
                     [
                       {"Owner#search$String_block", defs["stored_block"]},
                       {"Owner#search$Int32_block", defs["raw_yield"]},
                     ]
                   else
                     [
                       {"Owner#search$Int32_block", defs["raw_yield"]},
                       {"Owner#search$String_block", defs["stored_block"]},
                     ]
                   end
      candidates.each do |name, def_node|
        converter.__test_register_function_def(name, def_node, arena)
      end
      converter.__test_block_arg_requires_heap_proc?(
        "Owner#search$Int32_block",
        defs["raw_yield"],
        arena,
      ).should be_false
    end
  end

  it "selects a heap Proc for an exact stored-block definition, including a nested capture" do
    arena, defs = block_carrier_parse(<<-CRYSTAL)
    def stored_block(&block)
      block.call(1)
    end

    def nested_stored_block(&block)
      -> { block.call(1) }
    end
    CRYSTAL

    converter = Adamas::HIR::AstToHir.new(arena)
    converter.arena = arena
    converter.__test_block_arg_requires_heap_proc?(
      "Owner#stored_block$Int32_block",
      defs["stored_block"],
      arena,
    ).should be_true
    converter.__test_block_arg_requires_heap_proc?(
      "Owner#nested_stored_block$Int32_block",
      defs["nested_stored_block"],
      arena,
    ).should be_true
  end

  it "uses the materialized HIR carrier bit and rejects HIR bodies that yield" do
    arena, defs = block_carrier_parse(<<-CRYSTAL)
    def raw_yield(&block)
      yield
    end

    def stored_block(&block)
      block.call(1)
    end
    CRYSTAL

    converter = Adamas::HIR::AstToHir.new(arena)
    converter.arena = arena

    # A materialized heap-carrier signature remains authoritative even when
    # the selected source definition would otherwise suggest raw yield.
    converter.__test_materialized_block_arg_requires_heap_proc?(
      "Owner#selected$Int32_block",
      defs["raw_yield"],
      arena,
      body_emitted: true,
      block_parameter: true,
      heap_block_parameter: true,
      contains_yield: false,
    ).should be_true

    # The false bit is equally authoritative once the selected HIR body and
    # block slot have both been materialized.
    converter.__test_materialized_block_arg_requires_heap_proc?(
      "Owner#raw$Int32_block",
      defs["stored_block"],
      arena,
      body_emitted: true,
      block_parameter: true,
      heap_block_parameter: false,
      contains_yield: false,
    ).should be_false

    # A real HIR Yield means the callback uses the raw-yield carrier, even if
    # stale registration metadata says heap Proc.
    converter.__test_materialized_block_arg_requires_heap_proc?(
      "Owner#yielding$Int32_block",
      defs["stored_block"],
      arena,
      body_emitted: true,
      block_parameter: true,
      heap_block_parameter: true,
      contains_yield: true,
    ).should be_false
  end

  it "materializes forwarded, returned and instance-stored block values" do
    arena, defs = block_carrier_parse(<<-CRYSTAL)
    def forwarded(&block : -> Int32)
      deferred(&block)
    end

    def returned(&block : -> Int32)
      block
    end

    def assigned(&block : -> Int32)
      @callback = block
    end

    def instance_stored(&@block : -> Int32)
    end

    def unused(&block : -> Int32)
      1
    end
    CRYSTAL

    converter = Adamas::HIR::AstToHir.new(arena)
    converter.arena = arena
    ["forwarded", "returned", "assigned", "instance_stored"].each do |name|
      converter.__test_block_arg_requires_heap_proc?(
        "Owner##{name}_block", defs[name], arena,
      ).should be_true
    end
    converter.__test_block_arg_requires_heap_proc?(
      "Owner#unused_block", defs["unused"], arena,
    ).should be_false
  end

  it "falls back to the selected Def and arena for provisional HIR functions" do
    arena, defs = block_carrier_parse(<<-CRYSTAL)
    def stored_block(&block)
      block.call(1)
    end
    CRYSTAL

    converter = Adamas::HIR::AstToHir.new(arena)
    converter.arena = arena

    # `create_function` supplies a default false bit. Until a body and block
    # slot are materialized that default must not override the selected source.
    converter.__test_materialized_block_arg_requires_heap_proc?(
      "Owner#provisional$Int32_block",
      defs["stored_block"],
      arena,
      body_emitted: false,
      block_parameter: false,
      heap_block_parameter: false,
      contains_yield: false,
    ).should be_true

    # A partially admitted function body without its block parameter is also
    # provisional; source provenance remains selected and arena-backed.
    converter.__test_materialized_block_arg_requires_heap_proc?(
      "Owner#partial$Int32_block",
      defs["stored_block"],
      arena,
      body_emitted: true,
      block_parameter: false,
      heap_block_parameter: false,
      contains_yield: false,
    ).should be_true
  end
end
