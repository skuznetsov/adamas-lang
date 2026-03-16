# Edge case: Mixed virtual dispatch — arrays of parent type, method calls
# EXPECT: mixed_dispatch_all_ok

abstract class Node
  abstract def to_s : String
  abstract def children : Array(Node)
end

class TextNode < Node
  getter text : String

  def initialize(@text : String)
  end

  def to_s : String
    @text
  end

  def children : Array(Node)
    [] of Node
  end
end

class GroupNode < Node
  getter items : Array(Node)

  def initialize
    @items = [] of Node
  end

  def add(node : Node)
    @items << node
  end

  def to_s : String
    parts = @items.map { |n| n.to_s }
    "[#{parts.join(", ")}]"
  end

  def children : Array(Node)
    @items
  end
end

# Build a tree
root = GroupNode.new
root.add(TextNode.new("a"))
root.add(TextNode.new("b"))

inner = GroupNode.new
inner.add(TextNode.new("c"))
inner.add(TextNode.new("d"))
root.add(inner)

puts root.to_s

# Count all nodes recursively
def count_nodes(node : Node) : Int32
  total = 1
  node.children.each { |c| total += count_nodes(c) }
  total
end

puts count_nodes(root)

# Collect all text nodes
def collect_text(node : Node) : Array(String)
  result = [] of String
  if node.is_a?(TextNode)
    result << node.text
  end
  node.children.each do |child|
    collect_text(child).each { |t| result << t }
  end
  result
end

puts collect_text(root).join(",")

# Dispatch through interface
def print_tree(node : Node, indent : Int32 = 0) : Nil
  prefix = ""
  indent.times { prefix += "  " }
  if node.is_a?(TextNode)
    puts "#{prefix}Text: #{node.text}"
  elsif node.is_a?(GroupNode)
    puts "#{prefix}Group (#{node.items.size} children)"
    node.children.each { |c| print_tree(c, indent + 1) }
  end
end

print_tree(root)

puts "mixed_dispatch_all_ok"
