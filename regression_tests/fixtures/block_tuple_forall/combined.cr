lib LibC
  fun putchar(value : Int32) : Int32
end
class BindingBox(K, V)
end
class BlockMap
  def transform(& : Int32 -> Tuple(K, V)) forall K, V
    result = BindingBox(K, V).new
    yield 1
    result
  end
end
def accept_instances(value : BindingBox(Int32, Bool)) : Int32
  65
end
def accept_class_key(value : BindingBox(Int32.class, Bool)) : Int32
  66
end
def accept_class_value(value : BindingBox(Int32, Bool.class)) : Int32
  67
end
def accept_nested_class(value : BindingBox(Tuple(Int32.class, Int32), Bool)) : Int32
  68
end
def truth : Bool
  true
end
map = BlockMap.new
LibC.putchar(accept_instances(map.transform { |item| {item, true} }))
LibC.putchar(accept_class_key(map.transform { |item| {Int32, true} }))
LibC.putchar(accept_class_value(map.transform { |item| {item, Bool} }))
LibC.putchar(accept_nested_class(map.transform { |item| { {Int32, item}, true} }))
LibC.putchar(accept_class_key(map.transform do |item|
  kind = Int32
  {kind, true}
end))
LibC.putchar(accept_instances(map.transform { |item| {item, false} }))
LibC.putchar(10)
