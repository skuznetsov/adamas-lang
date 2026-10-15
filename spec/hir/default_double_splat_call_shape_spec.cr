require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_default_double_splat_shape(source : String) : Adamas::HIR::AstToHir
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

describe "default arguments before an empty double splat" do
  it "evaluates positional defaults before adding the empty named tuple slot" do
    converter = lower_default_double_splat_shape(<<-CRYSTAL)
      def default_slot_probe(seed : Int32, file = "default", line = 7, **options) : Int32
        seed + line
      end
      default_slot_probe(35)
      CRYSTAL
    main = converter.module.functions.find(&.name.ends_with?("main")).not_nil!
    call = main.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
      .find(&.method_name.starts_with?("default_slot_probe")).not_nil!
    call.args.size.should eq(4)
    call.args.map { |arg| main.blocks.flat_map(&.instructions).find { |value| value.id == arg }.not_nil!.type }[0, 3].should eq([
      Adamas::HIR::TypeRef::INT32,
      Adamas::HIR::TypeRef::STRING,
      Adamas::HIR::TypeRef::INT32,
    ])
    target = converter.module.functions.find { |function| function.name == call.method_name }.not_nil!
    target.params.size.should eq(call.args.size)
  end

  it "retains defaults and the named tuple when a nested yielding call needs a callback" do
    converter = lower_default_double_splat_shape(<<-CRYSTAL)
      def outer_slot_probe(&)
        yield 35
      end
      def middle_slot_probe(value, &)
        yield value
      end
      def inner_slot_probe(value, &)
        yield value
      end
      def callback_slot_probe(seed : Int32, file = "default", line = 7, **options, &)
        yield seed + line
      end
      outer_slot_probe do |first|
        middle_slot_probe(first) do |second|
          inner_slot_probe(second) do |third|
            callback_slot_probe(third) { |result| result }
          end
        end
      end
      CRYSTAL
    main = converter.module.functions.find(&.name.ends_with?("main")).not_nil!
    call = main.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
      .find(&.method_name.starts_with?("callback_slot_probe")).not_nil!
    target = converter.module.functions.find { |function| function.name == call.method_name }.not_nil!
    call.args.size.should eq(5)
    target.params.size.should eq(call.args.size)
  end
end
