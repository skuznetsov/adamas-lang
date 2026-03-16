# Complex: Class variables, constants, module-level state
# EXPECT: class_vars_all_ok

# --- Class variable basics ---
class IdGenerator
  @@next_id = 0

  def self.next : Int32
    @@next_id += 1
    @@next_id
  end

  def self.current : Int32
    @@next_id
  end
end

puts IdGenerator.next
puts IdGenerator.next
puts IdGenerator.next
puts IdGenerator.current

# --- Constants ---
module MathConstants
  PI = 3.14159
  E  = 2.71828

  def self.circle_area(r : Float64) : Float64
    PI * r * r
  end
end

puts MathConstants::PI
puts MathConstants.circle_area(1.0) > 3.0

# --- Class with class-level registry ---
class Animal2
  @@registry = [] of Animal2

  getter species : String

  def initialize(@species : String)
    @@registry << self
  end

  def self.count : Int32
    @@registry.size
  end

  def self.all_species : Array(String)
    @@registry.map { |a| a.species }
  end
end

Animal2.new("Dog")
Animal2.new("Cat")
Animal2.new("Bird")
puts Animal2.count
puts Animal2.all_species.join(",")

# --- Nested class with own constants ---
class Outer
  OUTER_VAL = 100

  class Inner
    INNER_VAL = 200

    def self.combined : Int32
      OUTER_VAL + INNER_VAL
    end
  end
end

puts Outer::OUTER_VAL
puts Outer::Inner::INNER_VAL
puts Outer::Inner.combined

# --- Module with mixin + class var ---
module Countable
  @@instances = 0

  def self.instance_count : Int32
    @@instances
  end
end

class Widget2
  @@count = 0

  def initialize
    @@count += 1
  end

  def self.count : Int32
    @@count
  end
end

Widget2.new
Widget2.new
Widget2.new
puts Widget2.count

puts "class_vars_all_ok"
