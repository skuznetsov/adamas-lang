require "spec"
require "file_utils"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/macro_expander"
require "../../src/compiler/lsp/ast_cache"

private def with_macro_expansion_program(source : String, cache_round_trip : Bool, &)
  dir = File.join(Dir.tempdir, "adamas_macro_consumer_#{Process.pid}_#{cache_round_trip}")
  FileUtils.mkdir_p(dir)
  source_path = File.join(dir, "consumer.cr")
  File.write(source_path, source)
  cache_path = Adamas::Compiler::LSP::AstCache.cache_path(source_path)

  lexer = Adamas::Compiler::Frontend::Lexer.new(source)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer, recovery_mode: false)
  parsed = parser.parse_program
  parser.diagnostics.should be_empty

  program = parsed
  arena = parsed.ast_arena
  if cache_round_trip
    Adamas::Compiler::LSP::AstCache.new(arena, parsed.roots, parsed.string_pool).save(source_path)
    loaded = Adamas::Compiler::LSP::AstCache.load(source_path).not_nil!
    program = Adamas::Compiler::Frontend::Program.new(loaded.arena, loaded.roots, loaded.string_pool)
    arena = loaded.arena
  end

  yield program, arena, source
ensure
  FileUtils.rm_rf(dir) if dir
  File.delete(cache_path) if cache_path && File.exists?(cache_path)
end

private def expand_macro(program, arena : Adamas::Compiler::Frontend::AstArena, source : String, name : String) : String
  definition = program.roots.compact_map do |root|
    arena[root].as?(Adamas::Compiler::Frontend::MacroDefNode)
  end.find do |node|
    String.new(node.name) == name
  end.not_nil!

  expander = Adamas::Compiler::Semantic::MacroExpander.new(program, arena, macro_source: source)
  output = expander.expand_literal(
    definition.body,
    variables: {} of String => Adamas::Compiler::Semantic::MacroValue,
  )
  expander.diagnostics.should be_empty
  output
end

MACRO_SOURCE = <<-CR
macro output_boundary_probe
  {% "LEAK" %} {{ "KEEP" }}
end

macro statement_effect_probe
  {% value = "SIDE" %}
  {{ value }}
end

macro nested_output_boundary_probe
  {% if true %}
    {% nested_value = "NESTED_SIDE" %}
    {% "NESTED_LEAK" %}
    {{ nested_value }}
  {% end %}
end

macro selected_if_effect_probe
  {% hits = [0] %}
  {% hits[0] = hits[0] + 1 if true %}
  {{ hits[0] }}
end

macro untaken_if_effect_probe
  {% hits = [0] %}
  {% hits[0] = hits[0] + 1 if false %}
  {{ hits[0] }}
end

macro selected_unless_effect_probe
  {% hits = [0] %}
  {% hits[0] = hits[0] + 1 unless false %}
  {{ hits[0] }}
end

macro untaken_unless_effect_probe
  {% hits = [0] %}
  {% hits[0] = hits[0] + 1 unless true %}
  {{ hits[0] }}
end
CR

describe "Macro directive output consumers" do
  [false, true].each do |cached|
    {"selected_if_effect_probe" => "1", "untaken_if_effect_probe" => "0",
     "selected_unless_effect_probe" => "1", "untaken_unless_effect_probe" => "0"}.each do |name, expected|
      it "executes the selected statement once for #{name}, cached=#{cached}" do
        with_macro_expansion_program(MACRO_SOURCE, cached) do |program, arena, source|
          expand_macro(program, arena, source, name).strip.should eq(expected)
        end
      end
    end
  end

  it "keeps statement-only literal values out of generated source for a parsed AST" do
    with_macro_expansion_program(MACRO_SOURCE, false) do |program, arena, source|
      output = expand_macro(program, arena, source, "output_boundary_probe").strip
      output.should eq("\"KEEP\"")
      output.includes?("LEAK").should be_false
    end
  end

  it "preserves statement effects and Crystal string-literal rendering for a parsed AST" do
    with_macro_expansion_program(MACRO_SOURCE, false) do |program, arena, source|
      output = expand_macro(program, arena, source, "statement_effect_probe").strip
      output.should eq("\"SIDE\"")
    end
  end

  it "preserves nested statement effects and output boundaries for a parsed AST" do
    with_macro_expansion_program(MACRO_SOURCE, false) do |program, arena, source|
      output = expand_macro(program, arena, source, "nested_output_boundary_probe").strip
      output.should eq("\"NESTED_SIDE\"")
      output.includes?("NESTED_LEAK").should be_false
    end
  end

  it "keeps statement-only literal values out of generated source after an AST-cache round trip" do
    with_macro_expansion_program(MACRO_SOURCE, true) do |program, arena, source|
      output = expand_macro(program, arena, source, "output_boundary_probe").strip
      output.should eq("\"KEEP\"")
      output.includes?("LEAK").should be_false
    end
  end

  it "preserves statement effects and Crystal string-literal rendering after an AST-cache round trip" do
    with_macro_expansion_program(MACRO_SOURCE, true) do |program, arena, source|
      output = expand_macro(program, arena, source, "statement_effect_probe").strip
      output.should eq("\"SIDE\"")
    end
  end

  it "preserves nested statement effects and output boundaries after an AST-cache round trip" do
    with_macro_expansion_program(MACRO_SOURCE, true) do |program, arena, source|
      output = expand_macro(program, arena, source, "nested_output_boundary_probe").strip
      output.should eq("\"NESTED_SIDE\"")
      output.includes?("NESTED_LEAK").should be_false
    end
  end
end
