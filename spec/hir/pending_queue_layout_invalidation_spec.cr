require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  # Test-only access to the live work queue and the exact layout invalidation
  # path.  The queue is intentionally seeded as pending work rather than
  # reconstructed after invalidation: process_pending_lower_functions walks
  # this same array by index while lowering is active.
  def __test_seed_layout_pending_queue(names : Array(String)) : Nil
    @pending_function_queue.clear
    names.each do |name|
      @pending_function_queue << name
      @function_lowering_states[name] = FunctionLoweringState::Pending
    end
  end

  def __test_add_body_for_layout_queue(name : String) : Nil
    function = @module.create_function(name, TypeRef::VOID)
    function.get_block(function.entry_block).terminator = Return.new
  end

  def __test_invalidate_layout_queue(class_name : String) : Nil
    invalidate_lowered_layout_functions(class_name)
  end

  def __test_layout_pending_queue : Array(String)
    @pending_function_queue.dup
  end

  def __test_layout_function_has_body?(name : String) : Bool
    @module.has_function_with_body?(name)
  end
end

describe "layout invalidation of the pending lowering queue" do
  it "preserves live queue order so no pending entries are skipped" do
    arena = Adamas::Compiler::Frontend::AstArena.new
    converter = Adamas::HIR::AstToHir.new(arena)
    queue = [
      "LayoutBox#first$Int32",
      "OtherType#keep$Int32",
      "LayoutBox#last$Int32",
    ]

    converter.__test_seed_layout_pending_queue(queue)
    queue.each { |name| converter.__test_add_body_for_layout_queue(name) }

    # This is the live-worklist shape at the point where a late layout bump
    # invalidates already-emitted LayoutBox methods.  Stale entries are safe:
    # the indexed consumer rechecks body/state and must still visit every
    # later entry in its original order.
    converter.__test_invalidate_layout_queue("LayoutBox")

    converter.__test_layout_pending_queue.should eq(queue)
    converter.__test_layout_function_has_body?("LayoutBox#first$Int32").should be_false
    converter.__test_layout_function_has_body?("OtherType#keep$Int32").should be_true
    converter.__test_layout_function_has_body?("LayoutBox#last$Int32").should be_false
  end
end
