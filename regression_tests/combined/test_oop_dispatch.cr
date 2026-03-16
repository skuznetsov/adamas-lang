# Combined: OOP, inheritance, modules, virtual dispatch, operator overloading
# EXPECT: oop_dispatch_all_ok

# --- Multi-level inheritance ---
class Base
  def name : String
    "Base"
  end

  def describe : String
    "I am #{name}"
  end
end

class Middle < Base
  def name : String
    "Middle"
  end
end

class Leaf < Middle
  def name : String
    "Leaf"
  end
end

puts Base.new.describe
puts Middle.new.describe
puts Leaf.new.describe

# --- Module inclusion with super ---
module Greetable
  def greet : String
    "Hello from #{self.class}"
  end
end

module Farewell
  def farewell : String
    "Goodbye from #{self.class}"
  end
end

class Person
  include Greetable
  include Farewell

  getter name : String

  def initialize(@name : String)
  end

  def to_s : String
    @name
  end
end

p = Person.new("Alice")
puts p.greet
puts p.farewell

# --- Virtual dispatch through parent type ---
class Shape
  def area : Float64
    0.0
  end

  def to_s : String
    "Shape(area=#{area})"
  end
end

class Circle < Shape
  getter radius : Float64

  def initialize(@radius : Float64)
  end

  def area : Float64
    3.14159 * @radius * @radius
  end

  def to_s : String
    "Circle(r=#{@radius})"
  end
end

class Rectangle < Shape
  getter width : Float64
  getter height : Float64

  def initialize(@width : Float64, @height : Float64)
  end

  def area : Float64
    @width * @height
  end

  def to_s : String
    "Rect(#{@width}x#{@height})"
  end
end

shapes = [] of Shape
shapes << Circle.new(5.0)
shapes << Rectangle.new(3.0, 4.0)
shapes << Circle.new(1.0)

shapes.each do |s|
  puts s.to_s
end

total_area = 0.0
shapes.each { |s| total_area += s.area }
puts total_area > 90.0

# --- is_a? type narrowing ---
shapes.each do |s|
  if s.is_a?(Circle)
    puts "circle radius=#{s.radius}"
  elsif s.is_a?(Rectangle)
    puts "rect area=#{s.area}"
  end
end

# --- Operator overloading ---
class Vec2
  getter x : Float64
  getter y : Float64

  def initialize(@x : Float64, @y : Float64)
  end

  def +(other : Vec2) : Vec2
    Vec2.new(@x + other.x, @y + other.y)
  end

  def -(other : Vec2) : Vec2
    Vec2.new(@x - other.x, @y - other.y)
  end

  def ==(other : Vec2) : Bool
    @x == other.x && @y == other.y
  end

  def to_s : String
    "(#{@x}, #{@y})"
  end
end

v1 = Vec2.new(1.0, 2.0)
v2 = Vec2.new(3.0, 4.0)
v3 = v1 + v2
puts v3.to_s
puts (v3 - v1) == v2

# --- Abstract class ---
abstract class Serializable
  abstract def serialize : String
end

class JsonNode < Serializable
  getter value : String

  def initialize(@value : String)
  end

  def serialize : String
    "\"#{@value}\""
  end
end

class IntNode < Serializable
  getter value : Int32

  def initialize(@value : Int32)
  end

  def serialize : String
    @value.to_s
  end
end

nodes = [] of Serializable
nodes << JsonNode.new("hello")
nodes << IntNode.new(42)
nodes.each { |n| puts n.serialize }

puts "oop_dispatch_all_ok"
