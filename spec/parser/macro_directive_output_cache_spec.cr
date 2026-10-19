require "spec"
require "file_utils"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/lsp/ast_cache"

private def macro_output_flags(arena : Adamas::Compiler::Frontend::AstArena)
  arena.nodes.compact_map do |node|
    node.as?(Adamas::Compiler::Frontend::MacroExpressionNode).try(&.output)
  end
end

private def with_macro_output_cache(name : String, &)
  dir = File.join(Dir.tempdir, "adamas_macro_output_#{Process.pid}_#{name}")
  FileUtils.mkdir_p(dir)
  path = File.join(dir, "sample.cr")
  File.write(path, "nil\n")
  cache_path = Adamas::Compiler::LSP::AstCache.cache_path(path)
  yield path, cache_path
ensure
  FileUtils.rm_rf(dir) if dir
  File.delete(cache_path) if cache_path && File.exists?(cache_path)
end

describe "Macro directive output boundaries" do
  it "keeps statement directives effect-only inside a macro body" do
    source = <<-CR
    macro output_probe
      {% value = 1 %}
      {{ value }}
      {% value = 2 %}
    end
    CR
    lexer = Adamas::Compiler::Frontend::Lexer.new(source)
    parser = Adamas::Compiler::Frontend::Parser.new(lexer, recovery_mode: false)
    program = parser.parse_program
    parser.diagnostics.should be_empty
    macro_output_flags(program.arena.as(Adamas::Compiler::Frontend::AstArena)).should eq([false, true, false])
  end

  it "roundtrips both effect-only and output-enabled nodes independently of parsing" do
    with_macro_output_cache("explicit_nodes") do |path, _|
      arena = Adamas::Compiler::Frontend::AstArena.new
      expression = arena.add(Adamas::Compiler::Frontend::NilNode.new(Adamas::Compiler::Frontend::Span.zero))
      effect = arena.add(Adamas::Compiler::Frontend::MacroExpressionNode.new(Adamas::Compiler::Frontend::Span.zero, expression, false))
      output = arena.add(Adamas::Compiler::Frontend::MacroExpressionNode.new(Adamas::Compiler::Frontend::Span.zero, expression, true))
      cache = Adamas::Compiler::LSP::AstCache.new(arena, [effect, output], Adamas::Compiler::Frontend::StringPool.new)
      cache.save(path)
      loaded = Adamas::Compiler::LSP::AstCache.load(path).not_nil!
      loaded.roots.size.should eq(2)
      macro_output_flags(loaded.arena).should eq([false, true])
    end
  end

  it "preserves nested macro piece output boundaries after loading from cache" do
    with_macro_output_cache("parsed_nodes") do |path, _|
      source = <<-CR
      macro output_probe
        {% value = 1 %}
        {{ value }}
        {% value = 2 %}
      end
      CR
      File.write(path, source)
      lexer = Adamas::Compiler::Frontend::Lexer.new(source)
      parser = Adamas::Compiler::Frontend::Parser.new(lexer, recovery_mode: false)
      program = parser.parse_program
      parser.diagnostics.should be_empty
      arena = program.arena.as(Adamas::Compiler::Frontend::AstArena)
      Adamas::Compiler::LSP::AstCache.new(arena, program.roots, lexer.string_pool).save(path)
      loaded = Adamas::Compiler::LSP::AstCache.load(path).not_nil!
      macro_output_flags(loaded.arena).should eq([false, true, false])
      macro_definition = loaded.arena[loaded.roots.first].as(Adamas::Compiler::Frontend::MacroDefNode)
      body = loaded.arena[macro_definition.body].as(Adamas::Compiler::Frontend::MacroLiteralNode)
      body.pieces.compact_map(&.expr).map { |id| loaded.arena[id].as(Adamas::Compiler::Frontend::MacroExpressionNode).output }.should eq([false, true, false])
    end
  end

  it "rejects a cache carrying the previous format version" do
    with_macro_output_cache("old_version") do |path, cache_path|
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
    end
  end
end
