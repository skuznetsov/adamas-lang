require "../spec_helper"
require "../../src/compiler/semantic/identity/arena_id"
require "../../src/compiler/semantic/identity/def_identity"

describe Adamas::Compiler::Semantic::ArenaId do
  it "assigns compile-scoped ids independently of owner tokens" do
    registry = Adamas::Compiler::Semantic::ArenaIdentityRegistry.new
    first_owner = Adamas::Compiler::Frontend::AstArena.new
    second_owner = Adamas::Compiler::Frontend::AstArena.new

    first = registry.id_for(first_owner)
    second = registry.id_for(second_owner)
    first_again = registry.id_for(first_owner)

    first.should eq(first_again)
    first.should_not eq(second)
    first.value.should eq(1_u64)
    second.value.should eq(2_u64)
    registry.size.should eq(2)
  end

  it "does not expose the owner token as the semantic id" do
    registry = Adamas::Compiler::Semantic::ArenaIdentityRegistry.new
    owner = Adamas::Compiler::Frontend::AstArena.new

    id = registry.id_for(owner)

    id.value.should_not eq(owner.object_id.to_u64)
  end

  it "constructs DefIdentity from the scoped id payload" do
    arena_id = Adamas::Compiler::Semantic::ArenaId.new(7_u64)

    identity = Adamas::Compiler::Semantic::DefIdentity.from_arena_id(arena_id, 19)

    identity.arena_id.should eq(7_u64)
    identity.expr_index.should eq(19)
  end
end
