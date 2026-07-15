require "spec"
require "../src/compiler/frontend/ast"

describe Adamas::Compiler::Frontend::PageArena do
  it "round-trips heterogeneous nodes" do
    arena = Adamas::Compiler::Frontend::PageArena.new
    nil_id = arena.add_typed(Adamas::Compiler::Frontend::NilNode.new(
      Adamas::Compiler::Frontend::Span.zero,
    ))
    bool_id = arena.add_typed(Adamas::Compiler::Frontend::BoolNode.new(
      Adamas::Compiler::Frontend::Span.zero,
      true,
    ))

    arena[nil_id].should be_a(Adamas::Compiler::Frontend::NilNode)
    arena[bool_id].as(Adamas::Compiler::Frontend::BoolNode).value.should be_true
    arena[nil_id]?.should be_a(Adamas::Compiler::Frontend::NilNode)
    arena[bool_id]?.as(Adamas::Compiler::Frontend::BoolNode).value.should be_true
  end

  it "round-trips nodes on both sides of a page boundary" do
    arena = Adamas::Compiler::Frontend::PageArena.new
    i = 0
    while i < Adamas::Compiler::Frontend::PageArena::PAGE - 1
      arena.add_typed(Adamas::Compiler::Frontend::NilNode.new(
        Adamas::Compiler::Frontend::Span.zero,
      ))
      i += 1
    end

    before_boundary = arena.add_typed(Adamas::Compiler::Frontend::BoolNode.new(
      Adamas::Compiler::Frontend::Span.zero,
      false,
    ))
    after_boundary = arena.add_typed(Adamas::Compiler::Frontend::NilNode.new(
      Adamas::Compiler::Frontend::Span.zero,
    ))

    before_boundary.index.should eq(Adamas::Compiler::Frontend::PageArena::PAGE - 1)
    after_boundary.index.should eq(Adamas::Compiler::Frontend::PageArena::PAGE)
    arena[before_boundary].as(Adamas::Compiler::Frontend::BoolNode).value.should be_false
    arena[after_boundary].should be_a(Adamas::Compiler::Frontend::NilNode)
    arena[before_boundary]?.should be_a(Adamas::Compiler::Frontend::BoolNode)
    arena[after_boundary]?.should be_a(Adamas::Compiler::Frontend::NilNode)
  end

  it "fails closed for invalid and out-of-bounds ids" do
    arena = Adamas::Compiler::Frontend::PageArena.new
    id = arena.add_typed(Adamas::Compiler::Frontend::NilNode.new(
      Adamas::Compiler::Frontend::Span.zero,
    ))

    arena[id]?.should be_a(Adamas::Compiler::Frontend::NilNode)
    arena[Adamas::Compiler::Frontend::ExprId.new(-1)]?.should be_nil
    arena[Adamas::Compiler::Frontend::ExprId.new(id.index + 1)]?.should be_nil
    expect_raises(IndexError) do
      arena[Adamas::Compiler::Frontend::ExprId.new(id.index + 1)]
    end
  end
end
