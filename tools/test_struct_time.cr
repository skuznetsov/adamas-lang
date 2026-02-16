require "../src/compiler/frontend/ast"
require "../src/compiler/frontend/lexer"
require "../src/compiler/frontend/parser"

alias Frontend = CrystalV2::Compiler::Frontend

TIME_PATH = "/opt/homebrew/Cellar/crystal/1.18.2/share/crystal/src/time.cr"

source = File.read(TIME_PATH)
lexer = Frontend::Lexer.new(source)
parser = Frontend::Parser.new(lexer, recovery_mode: true)
program = parser.parse_program

puts "=== Scanning time.cr for struct Time ==="
puts "Total roots: #{program.roots.size}"

class_count = 0
struct_count = 0
module_count = 0

program.roots.each_with_index do |root_id, idx|
  node = program.arena[root_id]
  case node
  when Frontend::ClassNode
    name_str = String.new(node.name)
    is_struct = node.is_struct == true
    if is_struct
      struct_count += 1
      puts "[#{idx}] STRUCT: #{name_str} (is_struct=#{node.is_struct})"
    else
      class_count += 1
      puts "[#{idx}] CLASS: #{name_str}"
    end
  when Frontend::ModuleNode
    module_count += 1
    name_str = String.new(node.name)
    puts "[#{idx}] MODULE: #{name_str}"
  end
end

puts ""
puts "Summary: #{class_count} classes, #{struct_count} structs, #{module_count} modules"
