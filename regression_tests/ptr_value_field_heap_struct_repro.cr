# Reducer: Pointer(T)#value then field read on heap-allocated struct (ptr.value.field).
# EXPECT: ptr_value_field_ok
struct Point
  @x : Int32
  @y : Int32

  def initialize(@x : Int32, @y : Int32)
  end

  def x
    @x
  end

  def y
    @y
  end
end

p = Pointer(Point).malloc(1)
p.value = Point.new(7, 8)
puts p.value.x
puts p.value.y
puts "ptr_value_field_ok"
