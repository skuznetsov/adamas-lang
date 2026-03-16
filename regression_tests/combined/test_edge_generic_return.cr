# Edge case: generic methods with various return types
# EXPECT: generic_return_all_ok

# Generic class with method returning different type
class Wrapper(T)
  getter value : T

  def initialize(@value : T)
  end

  def to_s : String
    "Wrapper(#{@value})"
  end

  def unwrap : T
    @value
  end
end

w1 = Wrapper.new(42)
puts w1.to_s
puts w1.unwrap

w2 = Wrapper.new("hello")
puts w2.to_s
puts w2.unwrap

# Generic method on non-generic class
class Converter
  def self.to_string(value : Int32) : String
    value.to_s
  end

  def self.to_int(value : String) : Int32
    value.to_i
  end
end

puts Converter.to_string(42)
puts Converter.to_int("123")

# Array of generic instances
wrappers = [Wrapper.new(1), Wrapper.new(2), Wrapper.new(3)]
wrappers.each { |w| puts w.unwrap }

# Nested generics
class Container2(T)
  def initialize
    @items = [] of T
  end

  def add(item : T)
    @items << item
  end

  def get(index : Int32) : T
    @items[index]
  end

  def size : Int32
    @items.size
  end

  def to_a : Array(T)
    @items.dup
  end
end

c = Container2(String).new
c.add("first")
c.add("second")
c.add("third")
puts c.size
puts c.get(0)
puts c.get(2)
puts c.to_a.join(",")

puts "generic_return_all_ok"
