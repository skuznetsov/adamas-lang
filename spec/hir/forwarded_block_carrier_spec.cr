require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_forwarded_block_carrier(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(
    program.arena,
    sources_by_arena: {program.arena.object_id.to_u64 => source},
  )
  converter.arena = program.arena
  converter.no_prelude = true
  main = [] of UInt64
  program.roots.each do |root|
    case node = program.arena[root]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
    else
      main << root.index.to_u64
    end
  end
  converter.lower_main(main)
  converter.flush_pending_functions
  converter
end

describe "forwarded named block carriers" do
  it "passes the captured block into an allocator without a block name suffix" do
    converter = lower_forwarded_block_carrier(<<-CRYSTAL)
      class Deferred
        @callback : Proc(Int32)
        def initialize(&@callback : -> Int32)
        end
        def call
          @callback.call
        end
      end

      def deferred(&callback : -> Int32)
        Deferred.new(&callback)
      end

      def make_deferred(value : Int32)
        deferred { value }
      end
      first = make_deferred(101)
      second = make_deferred(202)
      puts first.call
      puts second.call
    CRYSTAL
    function = converter.module.functions.find { |candidate| candidate.name == "deferred$block" }.not_nil!
    function.heap_block_param.should be_true
    callback = function.params.find(&.is_block).not_nil!
    call = function.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
      .find { |candidate| candidate.method_name.starts_with?("Deferred.new") }.not_nil!
    call.args.size.should eq(1)
    callback_arg = call.args.first
    if callback_arg != callback.id
      forwarded_copy = function.blocks.flat_map(&.instructions)
        .find { |instruction| instruction.id == callback_arg }.as?(Adamas::HIR::Copy)
      forwarded_copy.should_not be_nil
      forwarded_copy.not_nil!.source.should eq(callback.id)
      forwarded_copy.not_nil!.type.should eq(callback.type)
    end
  end

  it "returns an existing heap Proc without treating it as a function pointer" do
    converter = lower_forwarded_block_carrier(<<-CRYSTAL)
      def retained(&callback : -> Int32)
        callback
      end
      retained { 101 }
    CRYSTAL
    function = converter.module.functions.find { |candidate| candidate.name == "retained$block" }.not_nil!
    function.heap_block_param.should be_true
    callback = function.params.find(&.is_block).not_nil!
    returned = function.blocks.compact_map { |block| block.terminator.as?(Adamas::HIR::Return).try(&.value) }
    returned.should_not be_empty
    returned.each do |id|
      copy = function.blocks.flat_map(&.instructions).find { |instruction| instruction.id == id }.as?(Adamas::HIR::Copy)
      (id == callback.id || copy.try(&.source) == callback.id).should be_true
    end
    function.blocks.flat_map(&.instructions).any?(&.is_a?(Adamas::HIR::MakeProc)).should be_false
  end
end
