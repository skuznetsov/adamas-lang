require "../spec_helper"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_union_receiver_callback_inputs(receiver_name : String) : Array(String)?
    owner = "Tuple(Char)"
    input = CallResolutionInput.new("#{owner}#visit", 0, [] of TypeRef, true, false, false, nil)
    origin = find_included_module_def_origin_for_owner(owner, "visit", 0, true, selection_input: input)
    raise "missing concrete include" unless origin
    # A shared physical target identifies the declaration and arena. Its
    # callback still needs the application selected by the actual receiver.
    target = SelectedCallTarget.new("Tuple#visit$block", origin[0], origin[1])
    block_param_types_for_call(target.symbol_name, "Tuple#visit", type_ref_for_name(receiver_name),
      [] of TypeRef, selection_input: input, selected_source_target: target).try do |types|
      types.map { |type| get_type_name_from_ref(type) }
    end
  end
end

private def union_receiver_callback_converter
  source = <<-CRYSTAL
    module Leaf(E)
      def visit(&block : E -> Int32) : Int32
        1
      end
    end
    module Relay(U)
      include Leaf(U)
    end
    class DirectCallback
      include Relay(Char)
      def visit(&block : Int32 -> Int32) : Int32
        block.call(7)
      end
    end
    struct Tuple
      include Relay(Union(*T))
    end
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
  converter.no_prelude = true
  program.roots.each do |root|
    case node = arena[root]
    when Adamas::Compiler::Frontend::ModuleNode then converter.register_module(node)
    when Adamas::Compiler::Frontend::ClassNode  then converter.register_class(node)
    end
  end
  converter
end

describe "generic module callbacks on union receivers" do
  it "preserves a common transitive include binding across distinct tuple layouts" do
    converter = union_receiver_callback_converter
    converter.__test_union_receiver_callback_inputs("Tuple(Char) | Tuple(Char, Char)").should eq(["Char"])
  end

  it "does not use one arm's input when the other includes a different application" do
    converter = union_receiver_callback_converter
    inputs = converter.__test_union_receiver_callback_inputs("Tuple(Char) | Tuple(Int32)")
    inputs.should_not eq(["Char"])
    inputs.should_not eq(["Int32"])
  end

  it "requires the selected source declaration on every union arm" do
    converter = union_receiver_callback_converter
    inputs = converter.__test_union_receiver_callback_inputs("Tuple(Char) | DirectCallback")
    inputs.should_not eq(["Char"])
  end
end
