require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_allocator_shape(source : String) : Adamas::HIR::AstToHir
  result = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  ).parse_program
  converter = Adamas::HIR::AstToHir.new(
    result.arena,
    sources_by_arena: {result.arena.object_id.to_u64 => source},
  )
  converter.arena = result.arena
  classes = result.roots.compact_map { |id| result.arena[id].as?(Adamas::Compiler::Frontend::ClassNode) }
  defs = result.roots.compact_map { |id| result.arena[id].as?(Adamas::Compiler::Frontend::DefNode) }
  classes.each { |node| converter.register_class(node) }
  defs.each { |node| converter.register_function(node) }
  classes.each { |node| converter.lower_class(node) }
  defs.each { |node| converter.lower_def(node) }
  converter
end

private def allocator_shape_calls(converter : Adamas::HIR::AstToHir, name : String) : Array(Adamas::HIR::Call)
  function = converter.module.function_by_name(name).not_nil!
  function.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
end

describe "allocator identity across named and positional calls" do
  [true, false].each do |named_first|
    it "preserves both initializer bodies when named_first=#{named_first}" do
      calls = named_first ? "ReaderShape.new(at_end: \"count\")\nReaderShape.new(\"count\")" :
                            "ReaderShape.new(\"count\")\nReaderShape.new(at_end: \"count\")"
      converter = lower_allocator_shape(<<-CRYSTAL)
        struct ReaderShape
          getter pos : Int32
          def initialize(value : String, pos = 0)
            @pos = pos
          end
          def initialize(*, at_end value : String)
            @pos = 99
          end
        end
        def probe
          #{calls}
        end
      CRYSTAL

      allocators = allocator_shape_calls(converter, "probe").select(&.method_name.starts_with?("ReaderShape.new"))
      allocators.size.should eq(2)
      allocators.map(&.method_name).uniq.size.should eq(2)
      initializers = allocators.map do |allocator|
        allocator_shape_calls(converter, allocator.method_name).find(&.method_name.includes?("#initialize")).not_nil!
      end
      initializers.map(&.method_name).uniq.size.should eq(2)
      positional = initializers[named_first ? 1 : 0]
      positional.args.size.should eq(2)
      named = initializers[named_first ? 0 : 1]
      named.args.size.should eq(1)
    end
  end

  it "keeps distinct same-arity named-only initializer bodies" do
    converter = lower_allocator_shape(<<-CRYSTAL)
      class MultiNamed
        @marker : Int32
        def initialize(*, first value : Int32)
          @marker = 11
        end
        def initialize(*, second value : Int32)
          @marker = 22
        end
      end
      def probe
        MultiNamed.new(first: 1)
        MultiNamed.new(second: 2)
      end
    CRYSTAL
    allocators = allocator_shape_calls(converter, "probe").select(&.method_name.starts_with?("MultiNamed.new"))
    allocators.size.should eq(2)
    allocators.map(&.method_name).uniq.size.should eq(2)
    initializers = allocators.map do |allocator|
      allocator_shape_calls(converter, allocator.method_name).find(&.method_name.includes?("#initialize")).not_nil!
    end
    initializers.map(&.method_name).uniq.size.should eq(2)
  end
end
