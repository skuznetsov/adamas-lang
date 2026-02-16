require "../src/compiler/frontend/lexer"
require "../src/compiler/frontend/parser"

code = "pp M::A"
lexer = CrystalV2::Compiler::Frontend::Lexer.new(code)
program = CrystalV2::Compiler::Frontend::Parser.new(lexer, recovery_mode: true).parse_program

arena = program.arena

def print_tree(arena, expr_id, indent = 0)
  return if expr_id.invalid?
  node = arena[expr_id]
  prefix = "  " * indent
  puts "#{prefix}#{CrystalV2::Compiler::Frontend.node_kind(node)} span=#{node.span.start_column}-#{node.span.end_column} (offs=#{node.span.start_offset}-#{node.span.end_offset})"

  case node
  when CrystalV2::Compiler::Frontend::CallNode
    puts "#{prefix}  Callee:"
    print_tree(arena, node.callee, indent + 2) unless node.callee.invalid?
    puts "#{prefix}  Args:"
    node.args.each { |arg| print_tree(arena, arg, indent + 2) }
  when CrystalV2::Compiler::Frontend::PathNode
    if left = node.left
      puts "#{prefix}  Left:"
      print_tree(arena, left, indent + 2)
    end
    puts "#{prefix}  Right:"
    print_tree(arena, node.right, indent + 2)
  when CrystalV2::Compiler::Frontend::IdentifierNode
    puts "#{prefix}  name=#{node.name.try { |n| String.new(n) }}"
  end
end

puts "AST for: #{code}"
program.roots.each { |root| print_tree(arena, root) }
