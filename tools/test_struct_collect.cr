require "../src/compiler/frontend/ast"
require "../src/compiler/frontend/lexer"
require "../src/compiler/frontend/parser"
require "../src/compiler/semantic/context"
require "../src/compiler/semantic/symbol_table"
require "../src/compiler/semantic/symbol"
require "../src/compiler/semantic/collectors/symbol_collector"

alias Frontend = CrystalV2::Compiler::Frontend
alias Semantic = CrystalV2::Compiler::Semantic

TIME_PATH = "/opt/homebrew/Cellar/crystal/1.18.2/share/crystal/src/time.cr"

source = File.read(TIME_PATH)
lexer = Frontend::Lexer.new(source)
parser = Frontend::Parser.new(lexer, recovery_mode: true)
program = parser.parse_program

puts "=== Testing Symbol Collection for struct Time ==="
puts "Roots: #{program.roots.size}"

# Create context with symbol table
table = Semantic::SymbolTable.new
context = Semantic::Context.new(table)
collector = Semantic::SymbolCollector.new(program, context)
collector.collect

puts ""
puts "=== Checking symbol table ==="

# Look for Time
time_sym = table.lookup("Time")
if time_sym
  puts "Found Time: #{time_sym.class}"
  if time_sym.is_a?(Semantic::ClassSymbol)
    puts "  is_struct: #{time_sym.is_struct?}"
    puts "  superclass: #{time_sym.superclass_name}"
  end
else
  puts "Time NOT found in symbol table"
end

# List all symbols
puts ""
puts "=== All top-level symbols ==="
table.each_local_symbol do |name, sym|
  puts "  #{name}: #{sym.class.name.split("::").last}"
end
