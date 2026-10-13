require "spec"
require "file_utils"
require "random/secure"

require "./support/server_helper"

describe Adamas::Compiler::LSP::AstCache do
  it "roundtrips call nodes with blocks and named args" do
    dir = File.join(Dir.tempdir, "lsp_ast_cache_roundtrip_#{Random::Secure.hex(6)}")
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "sample.cr")
    cache_path = Adamas::Compiler::LSP::AstCache.cache_path(path)

    source = <<-CR
    foo(bar: 1) do
      2
    end
    CR
    File.write(path, source)

    lexer = Adamas::Compiler::Frontend::Lexer.new(source)
    parser = Adamas::Compiler::Frontend::Parser.new(lexer, recovery_mode: true)
    program = parser.parse_program

    parser.diagnostics.should be_empty
    arena = program.arena.as(Adamas::Compiler::Frontend::AstArena)

    Adamas::Compiler::LSP::AstCache.new(arena, program.roots, lexer.string_pool).save(path)

    loaded = Adamas::Compiler::LSP::AstCache.load(path)
    loaded.should_not be_nil

    loaded_program = Adamas::Compiler::Frontend::Program.new(loaded.not_nil!.arena, loaded.not_nil!.roots)
    call = loaded_program.arena[loaded_program.roots.first].as(Adamas::Compiler::Frontend::CallNode)

    call.block.should_not be_nil
    named_args = call.named_args
    named_args.should_not be_nil
    named_args.not_nil!.size.should eq(1)
    String.new(named_args.not_nil!.first.name).should eq("bar")
  ensure
    FileUtils.rm_rf(dir) if dir
    File.delete(cache_path) if cache_path && File.exists?(cache_path)
  end

  it "roundtrips forall parameter names for implicit and explicit return types" do
    dir = File.join(Dir.tempdir, "lsp_ast_cache_forall_#{Random::Secure.hex(6)}")
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "sample.cr")
    cache_path = Adamas::Compiler::LSP::AstCache.cache_path(path)

    source = <<-CR
    module CacheForall
      def implicit(
        obj : U,
        label : String = "default mentions forall V",
        & : T, U ->
      ) forall U
        obj
      end

      def explicit(
        obj : U,
        other : V,
        & : T, U ->
      ) : U forall U, V
        obj
      end
    end
    CR
    File.write(path, source)

    lexer = Adamas::Compiler::Frontend::Lexer.new(source)
    parser = Adamas::Compiler::Frontend::Parser.new(lexer, recovery_mode: true)
    program = parser.parse_program
    parser.diagnostics.should be_empty

    arena = program.arena.as(Adamas::Compiler::Frontend::AstArena)
    Adamas::Compiler::LSP::AstCache.new(arena, program.roots, lexer.string_pool).save(path)

    loaded = Adamas::Compiler::LSP::AstCache.load(path)
    loaded.should_not be_nil
    loaded_program = Adamas::Compiler::Frontend::Program.new(loaded.not_nil!.arena, loaded.not_nil!.roots)
    loaded_arena = loaded_program.arena.as(Adamas::Compiler::Frontend::AstArena)

    module_node = loaded_arena[loaded_program.roots.first].as(Adamas::Compiler::Frontend::ModuleNode)
    defs = {} of String => Adamas::Compiler::Frontend::DefNode
    module_node.body.not_nil!.each do |node_id|
      if def_node = loaded_arena[node_id].as?(Adamas::Compiler::Frontend::DefNode)
        defs[String.new(def_node.name)] = def_node
      end
    end

    implicit = defs["implicit"]
    implicit.return_type.should be_nil
    implicit.forall_type_params.map { |name| String.new(name) }.should eq(["U"])

    explicit = defs["explicit"]
    explicit.return_type.should_not be_nil
    explicit.forall_type_params.map { |name| String.new(name) }.should eq(["U", "V"])
  ensure
    FileUtils.rm_rf(dir) if dir
    File.delete(cache_path) if cache_path && File.exists?(cache_path)
  end
end
