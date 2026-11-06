require "spec"
require "file_utils"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/lsp/ast_cache"

private def with_macro_parameter_cache(name : String, &)
  dir = File.join(Dir.tempdir, "adamas_macro_parameters_#{Process.pid}_#{name}")
  FileUtils.mkdir_p(dir)
  path = File.join(dir, "sample.cr")
  File.write(path, "nil\n")
  cache_path = Adamas::Compiler::LSP::AstCache.cache_path(path)
  yield path, cache_path
ensure
  FileUtils.rm_rf(dir) if dir
  File.delete(cache_path) if cache_path && File.exists?(cache_path)
end

private def parsed_macro_parameter_program(source : String)
  lexer = Adamas::Compiler::Frontend::Lexer.new(source)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer, recovery_mode: false)
  program = parser.parse_program
  parser.diagnostics.should be_empty
  {program, lexer}
end

private def macro_parameter_fields(definition : Adamas::Compiler::Frontend::MacroDefNode)
  definition.params.map do |param|
    {param.name, param.external_name, param.prefix, param.default_source, param.named_only}
  end
end

describe "AST cache macro definition parameters" do
  it "roundtrips names, labels, defaults, splat prefixes, named-only state, and block parameters" do
    source = <<-CR
      macro positional_probe(value, "external" internal = "fallback")
        {{value}}
      end

      macro named_probe(*, required, "optional_label" optional = nil)
        {{required}}
      end

      macro splat_probe(*rest, **options, &block)
        {{block}}
      end

      macro empty_probe
        nil
      end
      CR
    program, lexer = parsed_macro_parameter_program(source)
    program.roots.size.should eq(4)

    arena = program.arena.as(Adamas::Compiler::Frontend::AstArena)
    definitions = program.roots.map { |root| arena[root].as(Adamas::Compiler::Frontend::MacroDefNode) }
    definitions.map { |definition| String.new(definition.name) }.should eq(["positional_probe", "named_probe", "splat_probe", "empty_probe"])

    original_fields = definitions.map { |definition| macro_parameter_fields(definition) }
    original_fields[0].map(&.[0]).should eq(["value", "internal"])
    original_fields[0].map(&.[4]).should eq([false, false])
    original_fields[0][1][1].not_nil!.should contain("external")
    original_fields[0][1][3].not_nil!.should contain("fallback")
    original_fields[1].map(&.[4]).should eq([true, true])
    original_fields[2].map(&.[2]).should eq(["*", "**", "&"])
    original_fields[2].map(&.[0]).should eq(["rest", "options", "block"])
    original_fields[2].map(&.[4]).should eq([false, false, false])
    original_fields[3].should be_empty

    with_macro_parameter_cache("roundtrip") do |path, _|
      File.write(path, source)
      Adamas::Compiler::LSP::AstCache.new(arena, program.roots, lexer.string_pool).save(path)
      loaded = Adamas::Compiler::LSP::AstCache.load(path).not_nil!
      loaded_definitions = loaded.roots.map do |root|
        loaded.arena[root].as(Adamas::Compiler::Frontend::MacroDefNode)
      end
      loaded_definitions.map { |definition| String.new(definition.name) }.should eq(["positional_probe", "named_probe", "splat_probe", "empty_probe"])
      loaded_definitions.map { |definition| macro_parameter_fields(definition) }.should eq(original_fields)
    end
  end

  it "rejects the previous cache format header after adding parameter fields" do
    with_macro_parameter_cache("old_header") do |path, cache_path|
      arena = Adamas::Compiler::Frontend::AstArena.new
      pool = Adamas::Compiler::Frontend::StringPool.new
      body = arena.add(Adamas::Compiler::Frontend::NilNode.new(Adamas::Compiler::Frontend::Span.zero))
      definition = arena.add(Adamas::Compiler::Frontend::MacroDefNode.new(
        Adamas::Compiler::Frontend::Span.zero,
        pool.intern("header_probe".to_slice),
        body
      ))
      cache = Adamas::Compiler::LSP::AstCache.new(
        arena,
        [definition],
        pool
      )
      cache.save(path)
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
