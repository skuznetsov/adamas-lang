require "../src/compiler/frontend/parser"

code = "def foo(x : Int32, y : Bool)\n  x + (y ? 1 : 0)\nend\n"
arena = CrystalV2::Compiler::Frontend::Arena.new
parser = CrystalV2::Compiler::Frontend::Parser.new(code, arena)
roots = parser.parse

def print_tree(arena, expr_id, indent = 0)
  return if expr_id.invalid?
  node = arena[expr_id]
  prefix = "  " * indent
  puts "#{prefix}#{CrystalV2::Compiler::Frontend.node_kind(node)} span=#{node.span.start_offset}-#{node.span.end_offset}"

  case node
  when CrystalV2::Compiler::Frontend::DefNode
    puts "#{prefix}  Params:"
    node.params.each do |p|
      puts "#{prefix}    #{p.name.try { |n| String.new(n) }} span=#{p.span.start_offset}-#{p.span.end_offset}"
    end
    puts "#{prefix}  Body:"
    node.body.try &.each do |child|
      print_tree(arena, child, indent + 2)
    end
  when CrystalV2::Compiler::Frontend::BinaryOpNode
    print_tree(arena, node.left, indent + 1)
    print_tree(arena, node.right, indent + 1)
  when CrystalV2::Compiler::Frontend::TernaryNode
    print_tree(arena, node.condition, indent + 1)
    print_tree(arena, node.then_expr, indent + 1)
    print_tree(arena, node.else_expr, indent + 1)
  when CrystalV2::Compiler::Frontend::ParenthesizedNode
    print_tree(arena, node.inner, indent + 1)
  when CrystalV2::Compiler::Frontend::IdentifierNode
    puts "#{prefix}  name=#{node.name.try { |n| String.new(n) }}"
  end
end

puts "Roots: #{roots.size}"
roots.each do |root_id|
  print_tree(arena, root_id)
end
