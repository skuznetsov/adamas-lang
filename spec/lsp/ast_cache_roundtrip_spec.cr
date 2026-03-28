require "spec"
require "file_utils"
require "random/secure"

require "./support/server_helper"

describe CrystalV2::Compiler::LSP::AstCache do
  it "roundtrips call nodes with blocks and named args" do
    dir = File.join(Dir.tempdir, "lsp_ast_cache_roundtrip_#{Random::Secure.hex(6)}")
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "sample.cr")
    cache_path = CrystalV2::Compiler::LSP::AstCache.cache_path(path)

    source = <<-CR
    foo(bar: 1) do
      2
    end
    CR
    File.write(path, source)

    lexer = CrystalV2::Compiler::Frontend::Lexer.new(source)
    parser = CrystalV2::Compiler::Frontend::Parser.new(lexer, recovery_mode: true)
    program = parser.parse_program

    parser.diagnostics.should be_empty
    arena = program.arena.as(CrystalV2::Compiler::Frontend::AstArena)

    CrystalV2::Compiler::LSP::AstCache.new(arena, program.roots, lexer.string_pool).save(path)

    loaded = CrystalV2::Compiler::LSP::AstCache.load(path)
    loaded.should_not be_nil

    loaded_program = CrystalV2::Compiler::Frontend::Program.new(loaded.not_nil!.arena, loaded.not_nil!.roots)
    call = loaded_program.arena[loaded_program.roots.first].as(CrystalV2::Compiler::Frontend::CallNode)

    call.block.should_not be_nil
    named_args = call.named_args
    named_args.should_not be_nil
    named_args.not_nil!.size.should eq(1)
    String.new(named_args.not_nil!.first.name).should eq("bar")
  ensure
    FileUtils.rm_rf(dir) if dir
    File.delete(cache_path) if cache_path && File.exists?(cache_path)
  end
end
