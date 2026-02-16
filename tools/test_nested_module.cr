require "../src/compiler/frontend/ast"
require "../src/compiler/frontend/lexer"
require "../src/compiler/frontend/parser"

alias Frontend = CrystalV2::Compiler::Frontend

source = File.read("/opt/homebrew/Cellar/crystal/1.18.2/share/crystal/src/crystal/system/time.cr")
lexer = Frontend::Lexer.new(source)
parser = Frontend::Parser.new(lexer, recovery_mode: true)
program = parser.parse_program

puts "=== Parsing crystal/system/time.cr ==="
puts "Roots: #{program.roots.size}"

def show_modules(arena, id, indent)
  node = arena[id]
  case node
  when CrystalV2::Compiler::Frontend::ModuleNode
    name = String.new(node.name)
    puts "#{indent}ModuleNode name=#{name}"
    (node.body || [] of CrystalV2::Compiler::Frontend::ExprId).each do |body_id|
      show_modules(arena, body_id, indent + "  ")
    end
  end
end

program.roots.each_with_index do |root_id, idx|
  puts "[#{idx}]"
  show_modules(program.arena, root_id, "  ")
end
