require "../spec_helper"
require "../../src/compiler/frontend/ast"

alias VirtualFileSourceFrontend = Adamas::Compiler::Frontend

describe "VirtualArena file-local source coordinates" do
  it "maps a nonzero global offset to the exact backing node and local id" do
    prefix = VirtualFileSourceFrontend::AstArena.new
    prefix.add(VirtualFileSourceFrontend::NilNode.new(VirtualFileSourceFrontend::Span.zero))
    prefix.add(VirtualFileSourceFrontend::NilNode.new(VirtualFileSourceFrontend::Span.zero))
    file = VirtualFileSourceFrontend::AstArena.new
    first = file.add(VirtualFileSourceFrontend::NilNode.new(VirtualFileSourceFrontend::Span.zero))
    last = file.add(VirtualFileSourceFrontend::NilNode.new(VirtualFileSourceFrontend::Span.zero))
    virtual = VirtualFileSourceFrontend::VirtualArena.new
    virtual.add_file_arena("empty.cr", VirtualFileSourceFrontend::AstArena.new)
    virtual.add_file_arena("prefix.cr", prefix)
    virtual.add_file_arena("body.cr", file)

    [first, last].each do |local_id|
      global_id = VirtualFileSourceFrontend::ExprId.new(prefix.size + local_id.index)
      source_arena, source_id = virtual.file_source_for(global_id).not_nil!
      source_arena.same?(file).should be_true
      source_id.index.should eq(local_id.index)
      source_arena[source_id].same?(virtual[global_id]).should be_true
    end
    source_arena, source_id = virtual.file_source_for(VirtualFileSourceFrontend::ExprId.new(0)).not_nil!
    source_arena.same?(prefix).should be_true
    source_id.index.should eq(0)
  end

  it "keeps generated nodes outside the file-local coordinate contract" do
    file = VirtualFileSourceFrontend::AstArena.new
    file.add(VirtualFileSourceFrontend::NilNode.new(VirtualFileSourceFrontend::Span.zero))
    virtual = VirtualFileSourceFrontend::VirtualArena.new
    virtual.add_file_arena("file.cr", file)
    generated = virtual.add(VirtualFileSourceFrontend::NilNode.new(VirtualFileSourceFrontend::Span.zero))
    virtual[generated].should be_a(VirtualFileSourceFrontend::NilNode)
    virtual.file_source_for(generated).should be_nil
    virtual.file_source_for(VirtualFileSourceFrontend::ExprId.new(-1)).should be_nil
    virtual.file_source_for(VirtualFileSourceFrontend::ExprId.new(Int32::MAX)).should be_nil
    VirtualFileSourceFrontend::VirtualArena.new.file_source_for(VirtualFileSourceFrontend::ExprId.new(0)).should be_nil
  end

  it "returns the new file mapping after replacement while the old source stays alive" do
    old_file = VirtualFileSourceFrontend::AstArena.new
    old_file.add(VirtualFileSourceFrontend::NilNode.new(VirtualFileSourceFrontend::Span.zero))
    virtual = VirtualFileSourceFrontend::VirtualArena.new
    virtual.add_file_arena("file.cr", old_file)
    root = VirtualFileSourceFrontend::ExprId.new(0)
    old_source = virtual.file_source_for(root).not_nil!
    replacement = VirtualFileSourceFrontend::AstArena.new
    replacement.add(VirtualFileSourceFrontend::NilNode.new(VirtualFileSourceFrontend::Span.zero))
    virtual.replace_file_arena("file.cr", replacement)

    new_source = virtual.file_source_for(root).not_nil!
    new_source[0].same?(replacement).should be_true
    old_source[0].same?(old_file).should be_true
    old_source[0][old_source[1]].same?(new_source[0][new_source[1]]).should be_false
  end
end
