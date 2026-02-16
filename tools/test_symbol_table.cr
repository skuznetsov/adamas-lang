require "../src/compiler/frontend/lexer"
require "../src/compiler/frontend/parser"
require "../src/compiler/semantic/collectors/symbol_collector"
require "../src/compiler/semantic/context"

source = <<-CRYSTAL
class A
  @@cv = 1
  def self.cv
    @@cv
  end
end

module M
  class A
    @@cv = 2
    def self.cv
      @@cv
    end
  end
end
CRYSTAL

lexer = CrystalV2::Compiler::Frontend::Lexer.new(source)
parser = CrystalV2::Compiler::Frontend::Parser.new(lexer)
program = parser.parse_program

root_table = CrystalV2::Compiler::Semantic::SymbolTable.new
context = CrystalV2::Compiler::Semantic::Context.new(root_table)
collector = CrystalV2::Compiler::Semantic::SymbolCollector.new(program, context)
collector.collect

table = context.symbol_table

puts "=== Symbol Table Root ==="
table.each_local_symbol do |name, sym|
  puts "  #{name}: #{sym.class}"
end

puts "\n=== Looking up M ==="
m_sym = table.lookup("M")
puts "M symbol: #{m_sym.inspect}"

if m_sym.is_a?(CrystalV2::Compiler::Semantic::ModuleSymbol)
  puts "M.scope symbols:"
  m_sym.scope.each_local_symbol do |name, sym|
    puts "  #{name}: #{sym.class}"
    if sym.is_a?(CrystalV2::Compiler::Semantic::ClassSymbol)
      puts "    node_id: #{sym.node_id}"
    end
  end
  
  puts "\n=== Looking up M::A ==="
  a_in_m = m_sym.scope.lookup("A")
  puts "M::A symbol: #{a_in_m.inspect}"
  if a_in_m.is_a?(CrystalV2::Compiler::Semantic::ClassSymbol)
    puts "  node_id: #{a_in_m.node_id}, invalid? #{a_in_m.node_id.invalid?}"
  end
end

puts "\n=== Looking up top-level A ==="
a_sym = table.lookup("A")
puts "A symbol: #{a_sym.inspect}"
if a_sym.is_a?(CrystalV2::Compiler::Semantic::ClassSymbol)
  puts "  node_id: #{a_sym.node_id}, invalid? #{a_sym.node_id.invalid?}"
end
