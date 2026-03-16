# Combined: Generics, union types, nilable types
# EXPECT: generics_unions_all_ok

# --- Generic class ---
class Box(T)
  getter value : T

  def initialize(@value : T)
  end

  def map(&block : T -> U) : Box(U) forall U
    Box.new(yield @value)
  end

  def to_s : String
    "Box(#{@value})"
  end
end

int_box = Box.new(42)
puts int_box.value
puts int_box.to_s

str_box = int_box.map { |v| v.to_s }
puts str_box.value

# --- Generic with multiple type params ---
class Pair(A, B)
  getter first : A
  getter second : B

  def initialize(@first : A, @second : B)
  end

  def swap : Pair(B, A)
    Pair.new(@second, @first)
  end

  def to_s : String
    "(#{@first}, #{@second})"
  end
end

p = Pair.new(1, "hello")
puts p.to_s
puts p.swap.to_s

# --- Nilable types ---
def find_positive(arr : Array(Int32)) : Int32?
  arr.each do |n|
    return n if n > 0
  end
  nil
end

result = find_positive([-3, -2, -1, 5, 10])
if result
  puts "found: #{result}"
else
  puts "not found"
end

result2 = find_positive([-3, -2, -1])
if result2
  puts "found: #{result2}"
else
  puts "not found"
end

# --- Union types ---
alias IntOrString = Int32 | String

def describe_value(v : IntOrString) : String
  case v
  when Int32
    "integer #{v}"
  when String
    "string '#{v}'"
  else
    "unknown"
  end
end

puts describe_value(42)
puts describe_value("hello")

# --- Array of union ---
mixed = [] of IntOrString
mixed << 1
mixed << "two"
mixed << 3
mixed << "four"
puts mixed.size
mixed.each do |v|
  puts describe_value(v)
end

# --- Nilable with methods ---
class Config
  getter name : String
  getter debug : Bool

  def initialize(@name : String, @debug : Bool = false)
  end
end

def get_config(name : String) : Config?
  if name == "main"
    Config.new("main", true)
  else
    nil
  end
end

if cfg = get_config("main")
  puts cfg.name
  puts cfg.debug
end

if cfg = get_config("other")
  puts "should not reach"
else
  puts "config not found"
end

# --- Recursive generic (linked list) ---
class ListNode(T)
  getter value : T
  property next_node : ListNode(T)?

  def initialize(@value : T, @next_node : ListNode(T)? = nil)
  end
end

head = ListNode.new(1, ListNode.new(2, ListNode.new(3)))
node = head
count = 0
while node
  count += 1
  puts node.value
  node = node.next_node
end
puts "count=#{count}"

puts "generics_unions_all_ok"
