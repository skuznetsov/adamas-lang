require "../src/compiler/bootstrap_shims"
require "../src/compiler/frontend/parser"
require "../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __probe_split_generic_type_args(name : String)
    split_generic_type_args(name)
  end
end

source = "1\n"
lexer = Adamas::Compiler::Frontend::Lexer.new(source)
parser = Adamas::Compiler::Frontend::Parser.new(lexer)
parser.parse_program_roots
arena = parser.arena

sources_by_arena = {arena.object_id.to_u64 => source}
paths_by_arena = {arena.object_id.to_u64 => "probe.cr"}
main_arenas = [arena] of Adamas::Compiler::Frontend::ArenaLike

hir_module = Adamas::HIR::Module.new("probe")
converter = Adamas::HIR::AstToHir.new(
  arena,
  "probe.cr",
  sources_by_arena,
  paths_by_arena,
  main_arenas,
  hir_module,
  [] of String,
)

parts = converter.__probe_split_generic_type_args("String")
puts "OK parts=#{parts.join("|")}"
