require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_atomic_included_union_result(receiver : String, argument : String) : TypeRef
    infer_virtual_return_type_from_registered_generic_union_targets(
      receiver, "[]", [type_ref_for_name(argument)], false, false,
    )
  end

  def __test_atomic_included_union_type_name(type : TypeRef) : String
    get_type_name_from_ref(type)
  end

  def __test_atomic_included_union_target(receiver : String, argument : String)
    name = mangle_function_name("#{receiver}#[]", [type_ref_for_name(argument)], false)
    {
      name,
      @function_defs[name]?,
      @function_def_arenas[name]?,
      function_namespace_override_for(name),
      (function_type_param_map_for_name(name) || {} of String => String).dup,
    }
  end
end

private def lower_atomic_included_union_sources(module_source : String, receiver_source : String)
  module_parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(module_source),
  )
  module_program = module_parser.parse_program
  module_parser.diagnostics.should be_empty
  receiver_parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(receiver_source),
  )
  receiver_program = receiver_parser.parse_program
  receiver_parser.diagnostics.should be_empty
  module_arena = module_program.arena
  receiver_arena = receiver_program.arena
  converter = Adamas::HIR::AstToHir.new(
    module_arena,
    sources_by_arena: {
      module_arena.object_id.to_u64   => module_source,
      receiver_arena.object_id.to_u64 => receiver_source,
    },
    paths_by_arena: {
      module_arena.object_id.to_u64   => "/tmp/atomic_included_union_leaf.cr",
      receiver_arena.object_id.to_u64 => "/tmp/atomic_included_union_receiver.cr",
    },
    main_arenas: [receiver_arena] of Adamas::Compiler::Frontend::ArenaLike,
  )
  converter.no_prelude = true
  leaf = module_arena[module_program.roots.first].as(Adamas::Compiler::Frontend::ModuleNode)
  definition = leaf.body.not_nil!.compact_map do |id|
    module_arena[id].as?(Adamas::Compiler::Frontend::DefNode)
  end.first
  converter.register_module(leaf)
  converter.arena = receiver_arena
  main = [] of UInt64
  receiver_program.roots.each do |id|
    case node = receiver_arena[id]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
    else
      main << id.index.to_u64
    end
  end
  converter.lower_main(main)
  converter.flush_pending_functions
  {converter, definition, module_arena}
end

private def atomic_included_union_fixture(kind : String = "struct", annotated : Bool = true)
  result_annotation = annotated ? " : E" : ""
  module_source = <<-CRYSTAL
    module AtomicIncludedUnionLeaf(E)
      def [](index : UInt8 | UInt16)#{result_annotation}
        @payload
      end
    end
    CRYSTAL
  receiver_source = <<-CRYSTAL
    #{kind} AtomicIncludedUnionBox(T)
      include AtomicIncludedUnionLeaf(Int32)

      def initialize(@payload : Int32)
      end

      # This incompatible direct sibling has the same method name and arity.
      # It must not supply the selected integer-index method's return type.
      def [](index : Bool) : self
        self
      end
    end

    AtomicIncludedUnionBox(UInt32).new(65)
    AtomicIncludedUnionBox(UInt64).new(66)
    CRYSTAL
  lower_atomic_included_union_sources(module_source, receiver_source)
end

private def assert_atomic_included_union_result(converter : Adamas::HIR::AstToHir) : Nil
  result = converter.__test_atomic_included_union_result(
    "AtomicIncludedUnionBox(UInt32) | AtomicIncludedUnionBox(UInt64)",
    "UInt8 | UInt16",
  )
  converter.__test_atomic_included_union_type_name(result).should eq("Int32")
end

describe "atomic included-module source ownership with equal result ABI" do
  it "uses the compatible included index result instead of an own same-arity sibling" do
    converter, _, _ = atomic_included_union_fixture

    assert_atomic_included_union_result(converter)
  end

  it "retains the exact leaf source, fixed E, and distinct receiver T binding per arm" do
    converter, definition, module_arena = atomic_included_union_fixture
    assert_atomic_included_union_result(converter)

    ["UInt32", "UInt64"].each do |element|
      name, selected, arena, namespace, bindings = converter.__test_atomic_included_union_target(
        "AtomicIncludedUnionBox(#{element})", "UInt8 | UInt16",
      )
      selected.should be(definition)
      arena.should be(module_arena)
      namespace.should eq("AtomicIncludedUnionLeaf")
      bindings["E"].should eq("Int32")
      bindings["T"].should eq(element)
      name.should start_with("AtomicIncludedUnionBox(#{element})#[]$")
    end

    # Reusing the published target must not replace a module binding with the
    # other receiver arm or resurrect the direct Bool sibling's source.
    assert_atomic_included_union_result(converter)
    converter.__test_atomic_included_union_target(
      "AtomicIncludedUnionBox(UInt32)", "UInt8 | UInt16",
    )[1].should be(definition)
  end

  it "infers an unannotated included body under the same concrete module frame" do
    converter, definition, module_arena = atomic_included_union_fixture(annotated: false)

    assert_atomic_included_union_result(converter)
    selected = converter.__test_atomic_included_union_target(
      "AtomicIncludedUnionBox(UInt64)", "UInt8 | UInt16",
    )
    selected[1].should be(definition)
    selected[2].should be(module_arena)
  end

  it "rejects an argument accepted by neither the direct nor included overload" do
    converter, _, _ = atomic_included_union_fixture

    error = expect_raises(Adamas::HIR::LoweringError) do
      converter.__test_atomic_included_union_result(
        "AtomicIncludedUnionBox(UInt32) | AtomicIncludedUnionBox(UInt64)",
        "Char",
      )
    end
    error.message.not_nil!.should contain("incompatible explicit arguments")
    error.message.not_nil!.should contain("#[]")
  end

  it "keeps the selected module frame for generic reference-class arms too" do
    converter, definition, module_arena = atomic_included_union_fixture("class")

    assert_atomic_included_union_result(converter)
    selected = converter.__test_atomic_included_union_target(
      "AtomicIncludedUnionBox(UInt32)", "UInt8 | UInt16",
    )
    selected[1].should be(definition)
    selected[2].should be(module_arena)
    selected[4]["E"].should eq("Int32")
  end

  it "preserves ordinary non-generic included-call lowering as a control" do
    module_source = <<-CRYSTAL
      module AtomicPlainIncludedIndexLeaf
        def [](index : UInt8 | UInt16) : Int32
          65
        end
      end
      CRYSTAL
    receiver_source = <<-CRYSTAL
      class AtomicPlainIncludedIndexBox
        include AtomicPlainIncludedIndexLeaf
      end

      def atomic_plain_included_index_probe(index : UInt8 | UInt16)
        AtomicPlainIncludedIndexBox.new[index]
      end

      atomic_plain_included_index_probe(0_u8)
      atomic_plain_included_index_probe(0_u16)
      CRYSTAL
    converter, _, module_arena = lower_atomic_included_union_sources(module_source, receiver_source)
    calls = converter.module.functions.flat_map(&.blocks).flat_map(&.instructions)
      .select(Adamas::HIR::Call).select { |call| call.method_name.includes?("AtomicPlainIncludedIndexBox#[]") }
    calls.should_not be_empty
    calls.each do |call|
      call.type.should eq(Adamas::HIR::TypeRef::INT32)
      target = converter.module.function_by_name(call.method_name).not_nil!
      target.return_type.should eq(Adamas::HIR::TypeRef::INT32)
      converter.module.has_function_with_body?(target.name).should be_true
      target.definition_location.not_nil!.path.should eq("/tmp/atomic_included_union_leaf.cr")
    end
    module_arena.should_not be(converter.arena)
  end
end
