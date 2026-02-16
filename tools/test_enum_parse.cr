require "../src/compiler/frontend/lexer"
require "../src/compiler/frontend/parser"

code = <<-CODE
class UseTreeStore(T)
  enum SlugType : UInt8
    Static
    Dynamic
  end
end
CODE

puts "Testing WITHOUT recovery mode:"
lexer = CrystalV2::Compiler::Frontend::Lexer.new(code)
parser = CrystalV2::Compiler::Frontend::Parser.new(lexer, recovery_mode: false)
program = parser.parse_program

puts "Diagnostics: #{program.diagnostics.size}"
program.diagnostics.each do |d|
  puts "  #{d.span.start_line + 1}:#{d.span.start_column + 1}: #{d.message}"
end

puts "\nTesting WITH recovery mode:"
lexer2 = CrystalV2::Compiler::Frontend::Lexer.new(code)
parser2 = CrystalV2::Compiler::Frontend::Parser.new(lexer2, recovery_mode: true)
program2 = parser2.parse_program

puts "Diagnostics: #{program2.diagnostics.size}"
program2.diagnostics.each do |d|
  puts "  #{d.span.start_line + 1}:#{d.span.start_column + 1}: #{d.message}"
end
