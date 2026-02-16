require "../src/compiler/frontend/ast"
require "../src/compiler/frontend/lexer"
require "../src/compiler/frontend/parser"

alias Frontend = CrystalV2::Compiler::Frontend

source = "module Crystal::System::Time\nend"
lexer = Frontend::Lexer.new(source)
parser = Frontend::Parser.new(lexer, recovery_mode: true)
program = parser.parse_program

puts "=== Parsing module Crystal::System::Time ==="
puts "Roots: #{program.roots.size}"

def show_node(arena, id, indent)
  node = arena[id]
  case node
  when Frontend::ModuleNode
    name = String.new(node.name)
    puts "#{indent}ModuleNode name=\"#{name}\""
    (node.body || [] of Frontend::ExprId).each do |body_id|
      show_node(arena, body_id, indent + "  ")
    end
  when Frontend::PathNode
    puts "#{indent}PathNode"
  when Frontend::IdentifierNode
    name = String.new(node.name)
    puts "#{indent}IdentifierNode name=\"#{name}\""
  else
    puts "#{indent}#{node.class.name.split("::").last}"
  end
end

program.roots.each_with_index do |root_id, idx|
  puts "[#{idx}]"
  show_node(program.arena, root_id, "  ")
end
