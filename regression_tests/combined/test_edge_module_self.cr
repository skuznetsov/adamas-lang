# Edge case: module method accessing self in different contexts
# EXPECT: module_self_all_ok

# Module method that accesses instance vars through self
module Named
  def display_name : String
    "name=#{name}"
  end
end

class User
  include Named
  getter name : String

  def initialize(@name : String)
  end
end

u = User.new("Alice")
puts u.display_name

# Module with self-referencing method (no self.class — that's a known bug)
module Measurable
  def measure_info : String
    "size=#{size}"
  end
end

class MyList
  include Measurable

  def initialize
    @items = [] of Int32
  end

  def add(item : Int32)
    @items << item
  end

  def size : Int32
    @items.size
  end
end

list = MyList.new
list.add(1)
list.add(2)
list.add(3)
puts list.measure_info

# Multiple modules with same method name (different modules)
module Printable2
  def info : String
    "printable"
  end
end

module Debuggable
  def debug : String
    "debug"
  end
end

class Widget3
  include Printable2
  include Debuggable

  def to_s : String
    "Widget3"
  end
end

w = Widget3.new
puts w.info
puts w.debug
puts w.to_s

puts "module_self_all_ok"
