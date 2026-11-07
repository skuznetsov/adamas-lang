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
def accept(value : BindingBox(Int32.class, Bool)) : Int32
  65
end
LibC.putchar(accept(BlockMap.new.transform do |item|
  kind = Int32
  {kind, true}
end))
LibC.putchar(10)
