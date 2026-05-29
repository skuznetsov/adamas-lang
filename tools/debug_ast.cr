require "../src/compiler/frontend/lexer"
require "../src/compiler/frontend/parser"

source = <<-CR
def main : Int32
  c = Counter.new()
  c.increment()
  c.get()
end
CR

lexer = Adamas::Compiler::Frontend::Lexer.new(source)
parser = Adamas::Compiler::Frontend::Parser.new(lexer)
result = parser.parse_program
arena = result.arena

def dump_node(arena, expr_id, indent = 0)
  node = arena[expr_id]
  prefix = "  " * indent
  puts "#{prefix}#{node.class.name.split("::").last}"

  case node
  when Adamas::Compiler::Frontend::DefNode
    puts "#{prefix}  name: #{String.new(node.name)}"
    node.body.try &.each { |e| dump_node(arena, e, indent + 1) }
  when Adamas::Compiler::Frontend::AssignNode
    puts "#{prefix}  target:"
    dump_node(arena, expr_id: node.target, indent: indent + 2)
    puts "#{prefix}  value:"
    dump_node(arena, expr_id: node.value, indent: indent + 2)
  when Adamas::Compiler::Frontend::CallNode
    puts "#{prefix}  callee:"
    dump_node(arena, expr_id: node.callee, indent: indent + 2)
    puts "#{prefix}  args: #{node.args.size}"
  when Adamas::Compiler::Frontend::MemberAccessNode
    puts "#{prefix}  object:"
    dump_node(arena, expr_id: node.object, indent: indent + 2)
    puts "#{prefix}  member: #{String.new(node.member)}"
  when Adamas::Compiler::Frontend::IdentifierNode
    puts "#{prefix}  name: #{String.new(node.name)}"
  when Adamas::Compiler::Frontend::ConstantNode
    puts "#{prefix}  name: #{String.new(node.name)}"
  end
end

result.roots.each do |expr_id|
  dump_node(arena, expr_id)
end
