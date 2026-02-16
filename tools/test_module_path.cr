require "../src/compiler/frontend/ast"
require "../src/compiler/frontend/lexer"
require "../src/compiler/frontend/parser"

alias Frontend = CrystalV2::Compiler::Frontend

source = "module Time::TZ\nend"
lexer = Frontend::Lexer.new(source)
parser = Frontend::Parser.new(lexer, recovery_mode: true)
program = parser.parse_program

puts "=== Parsing module Time::TZ ==="
puts "Roots: #{program.roots.size}"

program.roots.each_with_index do |root_id, idx|
  node = program.arena[root_id]
  case node
  when Frontend::ModuleNode
    name_str = String.new(node.name)
    puts "[#{idx}] MODULE name=\"#{name_str}\""
  end
end
