require "spec"
require "file_utils"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/lsp/ast_cache"

private def unpack_cache_pattern(arena : Adamas::Compiler::Frontend::AstArena, id : Adamas::Compiler::Frontend::ExprId) : String
  case node = arena[id]
  when Adamas::Compiler::Frontend::IdentifierNode
    String.new(node.name)
  when Adamas::Compiler::Frontend::TupleLiteralNode
    "(" + node.elements.map { |child| unpack_cache_pattern(arena, child) }.join(",") + ")"
  when Adamas::Compiler::Frontend::SplatNode
    "*" + unpack_cache_pattern(arena, node.expr)
  else
    raise "Unexpected block pattern node: #{node.class}"
  end
end

describe "Block destructuring AST cache" do
  it "retains input slots, nested patterns and splats across serialization" do
    dir = File.join(Dir.tempdir, "adamas_unpack_cache_#{Process.pid}")
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "sample.cr")
    source = <<-CR
    consume do |head, (first, (second, *rest)), tail|
      first
    end
    CR
    File.write(path, source)
    cache_path = Adamas::Compiler::LSP::AstCache.cache_path(path)

    lexer = Adamas::Compiler::Frontend::Lexer.new(source)
    parser = Adamas::Compiler::Frontend::Parser.new(lexer, recovery_mode: false)
    program = parser.parse_program
    parser.diagnostics.should be_empty
    arena = program.arena.as(Adamas::Compiler::Frontend::AstArena)
    Adamas::Compiler::LSP::AstCache.new(arena, program.roots, lexer.string_pool).save(path)

    loaded = Adamas::Compiler::LSP::AstCache.load(path).not_nil!
    loaded.roots.size.should eq(program.roots.size)
    call = loaded.arena[loaded.roots.first].as(Adamas::Compiler::Frontend::CallNode)
    block = loaded.arena[call.block.not_nil!].as(Adamas::Compiler::Frontend::BlockNode)
    block.params.not_nil!.size.should eq(3)
    block.params.not_nil!.map { |param| String.new(param.name.not_nil!) }.should eq(["head", "__block_unpack$1", "tail"])
    patterns = block.unpacks.not_nil!
    patterns.size.should eq(1)
    patterns.first[0].should eq(1)
    unpack_cache_pattern(loaded.arena, patterns.first[1]).should eq("(first,(second,*rest))")
    block.body.size.should eq(1)
    String.new(loaded.arena[block.body.first].as(Adamas::Compiler::Frontend::IdentifierNode).name).should eq("first")
  ensure
    FileUtils.rm_rf(dir) if dir
    File.delete(cache_path) if cache_path && File.exists?(cache_path)
  end

  it "rejects caches from the format without block patterns" do
    dir = File.join(Dir.tempdir, "adamas_unpack_old_cache_#{Process.pid}")
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "sample.cr")
    File.write(path, "nil\n")
    cache_path = Adamas::Compiler::LSP::AstCache.cache_path(path)
    arena = Adamas::Compiler::Frontend::AstArena.new
    value = arena.add(Adamas::Compiler::Frontend::NilNode.new(Adamas::Compiler::Frontend::Span.zero))
    Adamas::Compiler::LSP::AstCache.new(arena, [value], Adamas::Compiler::Frontend::StringPool.new).save(path)
    Adamas::Compiler::LSP::AstCache.current_header?(path).should be_true
    File.open(cache_path, "r+b") do |io|
      io.seek(4)
      io.write_bytes(Adamas::Compiler::LSP::AstCache::VERSION - 1_u32, IO::ByteFormat::LittleEndian)
    end
    Adamas::Compiler::LSP::AstCache.current_header?(path).should be_false
    Adamas::Compiler::LSP::AstCache.load(path).should be_nil
  ensure
    FileUtils.rm_rf(dir) if dir
    File.delete(cache_path) if cache_path && File.exists?(cache_path)
  end
end
