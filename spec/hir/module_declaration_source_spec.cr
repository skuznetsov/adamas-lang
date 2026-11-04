require "../spec_helper"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/hir/ast_to_hir"

private def parse_module_declaration(source : String)
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  program
end

describe "module declaration source" do
  it "rejects the same slot and name in a foreign arena" do
    source = "module ReceiptOwner\n  nil\n  class Child\n  end\nend\n"
    target = parse_module_declaration(source)
    decoy = parse_module_declaration(source)
    id = target.roots.first
    id.should eq(decoy.roots.first)
    node = target.arena[id].as(Adamas::Compiler::Frontend::ModuleNode)
    converter = Adamas::HIR::AstToHir.new(decoy.arena)
    converter.no_prelude = true

    expect_raises(Adamas::HIR::LoweringError, /module declaration source/) do
      converter.register_module(node, id)
    end
  end

  it "reads file-local children through the exact nonzero-offset virtual slot" do
    program = parse_module_declaration("module ReceiptOwner\n  nil\n  class Child\n  end\nend\n")
    file_arena = program.arena.as(Adamas::Compiler::Frontend::AstArena)
    prefix = parse_module_declaration("module Decoy\n  nil\n  class WrongChild\n  end\nend\n")
    prefix_arena = prefix.arena.as(Adamas::Compiler::Frontend::AstArena)
    virtual = Adamas::Compiler::Frontend::VirtualArena.new
    virtual.add_file_arena("decoy.cr", prefix_arena)
    virtual.add_file_arena("owner.cr", file_arena)
    id = program.roots.first
    virtual_id = Adamas::Compiler::Frontend::ExprId.new(prefix_arena.size + id.index)
    node = file_arena[id].as(Adamas::Compiler::Frontend::ModuleNode)
    converter = Adamas::HIR::AstToHir.new(virtual)
    converter.no_prelude = true

    converter.register_module(node, virtual_id)
    converter.arena.same?(virtual).should be_true
    converter.class_info.has_key?("ReceiptOwner::Child").should be_true
    converter.class_info.has_key?("ReceiptOwner::WrongChild").should be_false
  end
end
