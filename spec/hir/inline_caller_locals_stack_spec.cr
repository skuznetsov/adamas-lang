require "spec"
require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_seed_inline_caller_frames(frames : Array(Hash(String, ValueId))) : Nil
    @inline_caller_locals_stack.clear
    @inline_caller_locals_stack.concat(frames)
  end

  def __test_inline_caller_frame_at(index : Int32) : Hash(String, ValueId)?
    inline_caller_locals_at?(index)
  end

  def __test_snapshot_inline_caller_frame_at(
    ctx : LoweringContext,
    index : Int32,
  ) : Hash(String, ValueId)?
    snapshot_active_inline_caller_locals(ctx, index)
  end
end

describe "inline caller locals stack lookup" do
  it "preserves frame identity for positive and negative indices" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    first = {"first" => 11_u32}
    second = {"second" => 22_u32}
    converter.__test_seed_inline_caller_frames([first, second])

    converter.__test_inline_caller_frame_at(0).not_nil!.object_id.should eq(first.object_id)
    converter.__test_inline_caller_frame_at(-1).not_nil!.object_id.should eq(second.object_id)
    converter.__test_inline_caller_frame_at(-2).not_nil!.object_id.should eq(first.object_id)
  end

  it "returns nil for positive and negative out-of-bounds indices" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_seed_inline_caller_frames([{"only" => 1_u32}])

    converter.__test_inline_caller_frame_at(1).should be_nil
    converter.__test_inline_caller_frame_at(-2).should be_nil
    converter.__test_inline_caller_frame_at(Int32::MAX).should be_nil
    converter.__test_inline_caller_frame_at(Int32::MIN).should be_nil

    converter.__test_seed_inline_caller_frames([] of Hash(String, Adamas::HIR::ValueId))
    converter.__test_inline_caller_frame_at(0).should be_nil
    converter.__test_inline_caller_frame_at(-1).should be_nil
  end

  it "copies the selected frame when making a caller snapshot" do
    arena = Adamas::Compiler::Frontend::AstArena.new
    converter = Adamas::HIR::AstToHir.new(arena)
    function = converter.module.create_function("snapshot_probe", Adamas::HIR::TypeRef::VOID)
    ctx = Adamas::HIR::LoweringContext.new(function, converter.module, arena)
    frame = {"value" => 7_u32}
    converter.__test_seed_inline_caller_frames([frame])

    snapshot = converter.__test_snapshot_inline_caller_frame_at(ctx, -1).not_nil!
    snapshot["value"].should eq(7_u32)
    snapshot.object_id.should_not eq(frame.object_id)
    snapshot["value"] = 9_u32
    frame["value"].should eq(7_u32)
  end
end
