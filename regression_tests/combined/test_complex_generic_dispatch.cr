# Complex: Generic types with virtual dispatch, mixed containers
# EXPECT: generic_dispatch_all_ok

# --- Generic container with virtual dispatch ---
abstract class Widget
  abstract def render : String
  abstract def width : Int32
end

class Label < Widget
  getter text : String

  def initialize(@text : String)
  end

  def render : String
    "Label(#{@text})"
  end

  def width : Int32
    @text.size
  end
end

class Button < Widget
  getter label : String
  getter disabled : Bool

  def initialize(@label : String, @disabled : Bool = false)
  end

  def render : String
    state = @disabled ? "disabled" : "active"
    "Button(#{@label}, #{state})"
  end

  def width : Int32
    @label.size + 4
  end
end

class Container < Widget
  getter children : Array(Widget)

  def initialize
    @children = [] of Widget
  end

  def add(child : Widget)
    @children << child
  end

  def render : String
    parts = @children.map { |c| c.render }
    "Container[#{parts.join(", ")}]"
  end

  def width : Int32
    @children.sum { |c| c.width }
  end
end

# Build a widget tree
root = Container.new
root.add(Label.new("Hello"))
root.add(Button.new("OK"))
root.add(Button.new("Cancel", true))

inner = Container.new
inner.add(Label.new("Nested"))
inner.add(Button.new("Go"))
root.add(inner)

puts root.render
puts root.width

# --- Generic class with constraints ---
class SortedList(T)
  def initialize
    @items = [] of T
  end

  def add(item : T)
    @items << item
    @items.sort!
  end

  def to_a : Array(T)
    @items.dup
  end

  def size : Int32
    @items.size
  end

  def first : T
    @items.first
  end

  def last : T
    @items.last
  end
end

sl = SortedList(Int32).new
sl.add(30)
sl.add(10)
sl.add(50)
sl.add(20)
puts sl.to_a.join(",")
puts sl.first
puts sl.last

sl2 = SortedList(String).new
sl2.add("cherry")
sl2.add("apple")
sl2.add("banana")
puts sl2.to_a.join(",")

# --- Hash with complex keys ---
class_counts = {} of String => Int32
["Dog", "Cat", "Dog", "Bird", "Cat", "Dog"].each do |name|
  class_counts[name] = (class_counts[name]? || 0) + 1
end
puts class_counts["Dog"]
puts class_counts["Cat"]
puts class_counts["Bird"]

puts "generic_dispatch_all_ok"
