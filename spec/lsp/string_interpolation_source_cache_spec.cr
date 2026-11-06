require "spec"
require "file_utils"
require "random/secure"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/lsp/ast_cache"

include Adamas::Compiler

describe "String interpolation expression source ownership" do
  it "retains block and conditional payloads through adjacent literals and the AST cache" do
    dir = File.join(Dir.tempdir, "interpolation_source_cache_#{Random::Secure.hex(6)}")
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "sample.cr")
    cache_path = LSP::AstCache.cache_path(path)
    source = %q(result = "pre#{produce { mark; "A" }}" "mid#{if flag
      "B"
    else
      "C"
    end}post") + "\n"
    File.write(path, source)
    lexer = Frontend::Lexer.new(source)
    parser = Frontend::Parser.new(lexer)
    program = parser.parse_program
    parser.diagnostics.should be_empty
    arena = program.arena.as(Frontend::AstArena)
    assignment = arena[program.roots.first].as(Frontend::AssignNode)
    interpolation = arena[assignment.value].as(Frontend::StringInterpolationNode)
    expected = [%q(produce { mark; "A" }), "if flag\n      \"B\"\n    else\n      \"C\"\n    end"]
    interpolation.pieces.select(&.kind.expression?).map(&.expression_source).should eq(expected)

    LSP::AstCache.new(arena, program.roots, lexer.string_pool).save(path)
    loaded = LSP::AstCache.load(path).not_nil!
    loaded_assignment = loaded.arena[loaded.roots.first].as(Frontend::AssignNode)
    loaded_interpolation = loaded.arena[loaded_assignment.value].as(Frontend::StringInterpolationNode)
    GC.collect
    loaded_interpolation.pieces.select(&.kind.expression?).map(&.expression_source).should eq(expected)
    expression_ids = loaded_interpolation.pieces.select(&.kind.expression?).map(&.expr.not_nil!)
    loaded.arena[expression_ids[0]].should be_a(Frontend::CallNode)
    loaded.arena[expression_ids[0]].as(Frontend::CallNode).block.should_not be_nil
    loaded.arena[expression_ids[1]].should be_a(Frontend::IfNode)
  ensure
    FileUtils.rm_rf(dir) if dir
    File.delete(cache_path) if cache_path && File.exists?(cache_path)
  end

  it "rejects cache headers from before interpolation payload source retention" do
    dir = File.join(Dir.tempdir, "interpolation_source_cache_version_#{Random::Secure.hex(6)}")
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "sample.cr")
    cache_path = LSP::AstCache.cache_path(path)
    source = %q(result = "#{value}") + "\n"
    File.write(path, source)
    lexer = Frontend::Lexer.new(source)
    parser = Frontend::Parser.new(lexer)
    program = parser.parse_program
    parser.diagnostics.should be_empty
    LSP::AstCache.new(program.arena.as(Frontend::AstArena), program.roots, lexer.string_pool).save(path)
    LSP::AstCache.load(path).should_not be_nil
    File.open(cache_path, "r+") do |io|
      io.seek(4)
      io.write_bytes(10_u32, IO::ByteFormat::LittleEndian)
    end
    LSP::AstCache.load(path).should be_nil
  ensure
    FileUtils.rm_rf(dir) if dir
    File.delete(cache_path) if cache_path && File.exists?(cache_path)
  end
end
