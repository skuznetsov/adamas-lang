require "../src/compiler/frontend/ast"
require "../src/compiler/frontend/lexer"
require "../src/compiler/frontend/parser"
require "../src/compiler/semantic/context"
require "../src/compiler/semantic/symbol_table"
require "../src/compiler/semantic/symbol"
require "../src/compiler/semantic/collectors/symbol_collector"

alias Frontend = CrystalV2::Compiler::Frontend
alias Semantic = CrystalV2::Compiler::Semantic

STDLIB = "/opt/homebrew/Cellar/crystal/1.18.2/share/crystal/src"

# Process files in same order as prelude
files = [
  "#{STDLIB}/crystal/system/time.cr",  # Dependencies first
  "#{STDLIB}/time.cr",                 # Main file
]

# Create shared context
table = Semantic::SymbolTable.new
context = Semantic::Context.new(table)

files.each do |path|
  puts "=== Processing #{path} ==="
  source = File.read(path)
  lexer = Frontend::Lexer.new(source)
  parser = Frontend::Parser.new(lexer, recovery_mode: true)
  program = parser.parse_program
  
  puts "  Roots: #{program.roots.size}"
  program.roots.each_with_index do |root_id, idx|
    node = program.arena[root_id]
    case node
    when Frontend::ClassNode
      name = String.new(node.name)
      puts "  [#{idx}] ClassNode name=#{name} is_struct=#{node.is_struct}"
    when Frontend::ModuleNode
      name = String.new(node.name)
      puts "  [#{idx}] ModuleNode name=#{name}"
    end
  end
  
  collector = Semantic::SymbolCollector.new(program, context)
  collector.collect
  
  time_sym = table.lookup("Time")
  if time_sym
    puts "  After collection - Time: #{time_sym.class.name.split("::").last}"
  else
    puts "  After collection - Time: NOT FOUND"
  end
  puts ""
end
