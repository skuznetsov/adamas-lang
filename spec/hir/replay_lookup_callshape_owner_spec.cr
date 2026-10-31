require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_replay_lookup_preserves_source_callshape(
    method : String,
    lookup_types : Array(TypeRef),
    has_block : Bool,
  ) : Tuple(String?, Bool, Array(TypeRef))
    base = "ReplayCallshapeParent##{method}"
    remember_callsite_arg_types(base, [] of TypeRef, [] of Bool)
    lower_function_if_needed(base)
    function = @module.function_by_name(base).not_nil!
    @module.has_function_with_body?(base).should be_true
    function.return_type.should eq(TypeRef::INT32)
    # Re-record the exact physical target's input after its initial consumer.
    # Ancestor selection has no authority to replace this retained demand.
    remember_callsite_arg_types(base, [] of TypeRef, [] of Bool)
    selected = lookup_concrete_broad_replay_ancestor(
      "ReplayCallshapeChild", "ReplayCallshapeParent", method, lookup_types, has_block, false,
    )
    # A lookup must not change a different physical target's exact input.
    restored = @pending_arg_types[base]
    {selected.try(&.[0]), restored.has_block, restored.types}
  end
end

private def replay_lookup_callshape_fixture
  source = <<-CRYSTAL
    class ReplayCallshapeParent
      def value : Int32
        65
      end
      def value(&) : Nil
        yield 66
      end
      def argument : Int32
        67
      end
      def argument(value : Int32) : Int32
        value
      end
      def alone : Int32
        68
      end
    end
    class ReplayCallshapeChild < ReplayCallshapeParent
    end
    CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  parsed = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(parsed.ast_arena, sources_by_arena: {parsed.ast_arena.object_id.to_u64 => source})
  converter.no_prelude = true
  parsed.roots.each do |id|
    converter.register_class(parsed.ast_arena[id].as(Adamas::Compiler::Frontend::ClassNode))
  end
  converter
end

describe "broad ancestor lookup and exact body call shapes" do
  it "does not overwrite a nilary no-block body while looking up its block sibling" do
    converter = replay_lookup_callshape_fixture
    selected, has_block, types = converter.__test_replay_lookup_preserves_source_callshape("value", [] of Adamas::HIR::TypeRef, true)
    selected.should eq("ReplayCallshapeParent#value$block")
    has_block.should be_false
    types.should be_empty
  end

  it "does not overwrite a nilary body while looking up a different arity" do
    converter = replay_lookup_callshape_fixture
    selected, has_block, types = converter.__test_replay_lookup_preserves_source_callshape("argument", [Adamas::HIR::TypeRef::INT32], false)
    selected.should eq("ReplayCallshapeParent#argument$Int32")
    has_block.should be_false
    types.should be_empty
  end

  it "leaves an existing body recipe intact when no compatible ancestor exists" do
    converter = replay_lookup_callshape_fixture
    selected, has_block, types = converter.__test_replay_lookup_preserves_source_callshape("alone", [] of Adamas::HIR::TypeRef, true)
    selected.should be_nil
    has_block.should be_false
    types.should be_empty
  end
end
