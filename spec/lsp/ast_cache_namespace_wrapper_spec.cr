require "spec"
require "file_utils"
require "random/secure"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/lsp/ast_cache"

module AstCacheNamespaceWrapperSpec
  def self.module_facts(arena : Adamas::Compiler::Frontend::AstArena, roots : Array(Adamas::Compiler::Frontend::ExprId))
    facts = [] of {String, Bool, Bool}
    roots.each { |root| collect_module_facts(arena, root, "", facts) }
    facts
  end

  private def self.collect_module_facts(
    arena : Adamas::Compiler::Frontend::AstArena,
    node_id : Adamas::Compiler::Frontend::ExprId,
    parent : String,
    facts : Array({String, Bool, Bool}),
  ) : Nil
    node = arena[node_id]
    case node
    when Adamas::Compiler::Frontend::ModuleNode
      path = parent + String.new(node.name)
      facts << {path, node.namespace_wrapper, node.absolute}
      if body = node.body
        body.each { |child| collect_module_facts(arena, child, path + "::", facts) }
      end
    when Adamas::Compiler::Frontend::ClassNode
      path = parent + String.new(node.name)
      if body = node.body
        body.each { |child| collect_module_facts(arena, child, path + "::", facts) }
      end
    end
  end
end

describe Adamas::Compiler::LSP::AstCache do
  it "roundtrips namespace provenance independently of absolute paths and real module nesting" do
    dir = File.join(Dir.tempdir, "lsp_ast_cache_namespace_#{Random::Secure.hex(6)}")
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "sample.cr")
    cache_path = Adamas::Compiler::LSP::AstCache.cache_path(path)
    source = <<-CR
    module Actual
      module Nested
      end
    end
    class Relative::Middle::Leaf
    end
    module Generic::Middle::Leaf(T)
    end
    class Enclosing
      class ::RootClass::Middle::Leaf
      end
      module ::RootModule::Middle::Leaf
      end
      module ::Single
      end
    end
    CR
    File.write(path, source)
    lexer = Adamas::Compiler::Frontend::Lexer.new(source)
    parser = Adamas::Compiler::Frontend::Parser.new(lexer)
    program = parser.parse_program
    parser.diagnostics.should be_empty
    arena = program.arena.as(Adamas::Compiler::Frontend::AstArena)
    expected = [
      {"Actual", false, false},
      {"Actual::Nested", false, false},
      {"Relative", true, false},
      {"Relative::Middle", true, false},
      {"Generic", true, false},
      {"Generic::Middle", true, false},
      {"Generic::Middle::Leaf", false, false},
      {"Enclosing::RootClass", true, true},
      {"Enclosing::RootClass::Middle", true, false},
      {"Enclosing::RootModule", true, true},
      {"Enclosing::RootModule::Middle", true, false},
      {"Enclosing::RootModule::Middle::Leaf", false, false},
      {"Enclosing::Single", false, true},
    ]
    AstCacheNamespaceWrapperSpec.module_facts(arena, program.roots).should eq(expected)
    Adamas::Compiler::LSP::AstCache.new(arena, program.roots, lexer.string_pool).save(path)

    loaded = Adamas::Compiler::LSP::AstCache.load(path).not_nil!
    AstCacheNamespaceWrapperSpec.module_facts(loaded.arena, loaded.roots).should eq(expected)
    generic = loaded.arena[loaded.roots[2]].as(Adamas::Compiler::Frontend::ModuleNode)
    middle = loaded.arena[generic.body.not_nil!.first].as(Adamas::Compiler::Frontend::ModuleNode)
    leaf = loaded.arena[middle.body.not_nil!.first].as(Adamas::Compiler::Frontend::ModuleNode)
    leaf.type_params.not_nil!.map { |name| String.new(name) }.should eq(["T"])
  ensure
    FileUtils.rm_rf(dir) if dir
    File.delete(cache_path) if cache_path && File.exists?(cache_path)
  end

  it "rejects an older schema instead of inventing namespace provenance" do
    dir = File.join(Dir.tempdir, "lsp_ast_cache_namespace_version_#{Random::Secure.hex(6)}")
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "sample.cr")
    cache_path = Adamas::Compiler::LSP::AstCache.cache_path(path)
    source = "class Outer::Leaf\nend"
    File.write(path, source)
    lexer = Adamas::Compiler::Frontend::Lexer.new(source)
    parser = Adamas::Compiler::Frontend::Parser.new(lexer)
    program = parser.parse_program
    parser.diagnostics.should be_empty
    Adamas::Compiler::LSP::AstCache.new(
      program.arena.as(Adamas::Compiler::Frontend::AstArena), program.roots, lexer.string_pool
    ).save(path)
    Adamas::Compiler::LSP::AstCache.current_header?(path).should be_true
    File.open(cache_path, "r+b") do |io|
      io.seek(Adamas::Compiler::LSP::AstCache::MAGIC.bytesize)
      io.write_bytes(8_u32, IO::ByteFormat::LittleEndian)
    end

    Adamas::Compiler::LSP::AstCache.current_header?(path).should be_false
    Adamas::Compiler::LSP::AstCache.load(path).should be_nil
  ensure
    FileUtils.rm_rf(dir) if dir
    File.delete(cache_path) if cache_path && File.exists?(cache_path)
  end
end
