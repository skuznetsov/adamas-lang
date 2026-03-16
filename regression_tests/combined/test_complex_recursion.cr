# Complex: Recursion patterns, tree traversal, memoization
# EXPECT: recursion_all_ok

# --- Basic recursion ---
def factorial(n : Int32) : Int64
  return 1_i64 if n <= 1
  n.to_i64 * factorial(n - 1)
end

puts factorial(10)

# --- Fibonacci (naive) ---
def fib(n : Int32) : Int32
  return n if n <= 1
  fib(n - 1) + fib(n - 2)
end

puts fib(10)

# --- Binary tree ---
class TreeNode
  getter value : Int32
  property left : TreeNode?
  property right : TreeNode?

  def initialize(@value : Int32)
    @left = nil
    @right = nil
  end
end

def tree_insert(node : TreeNode?, value : Int32) : TreeNode
  unless node
    return TreeNode.new(value)
  end
  if value < node.value
    node.left = tree_insert(node.left, value)
  elsif value > node.value
    node.right = tree_insert(node.right, value)
  end
  node
end

def inorder(node : TreeNode?) : Array(Int32)
  return [] of Int32 unless node
  inorder(node.left) + [node.value] + inorder(node.right)
end

def tree_depth(node : TreeNode?) : Int32
  return 0 unless node
  left_d = tree_depth(node.left)
  right_d = tree_depth(node.right)
  1 + Math.max(left_d, right_d)
end

root = nil.as(TreeNode?)
[5, 3, 7, 1, 4, 6, 8].each do |v|
  root = tree_insert(root, v)
end

puts inorder(root).join(",")
puts tree_depth(root)

# --- Mutual recursion ---
def is_even(n : Int32) : Bool
  return true if n == 0
  is_odd(n - 1)
end

def is_odd(n : Int32) : Bool
  return false if n == 0
  is_even(n - 1)
end

puts is_even(10)
puts is_odd(7)
puts is_even(3)

# --- Recursive string processing ---
def reverse_string(s : String) : String
  return s if s.size <= 1
  s[-1].to_s + reverse_string(s[0...-1])
end

puts reverse_string("hello")
puts reverse_string("a")
puts reverse_string("")

# --- Power set (exponential recursion) ---
def power_set(arr : Array(Int32)) : Array(Array(Int32))
  if arr.empty?
    return [[] of Int32]
  end
  first = arr[0]
  rest = power_set(arr[1..])
  result = [] of Array(Int32)
  rest.each do |subset|
    result << subset
    result << [first] + subset
  end
  result
end

ps = power_set([1, 2, 3])
puts ps.size

puts "recursion_all_ok"
