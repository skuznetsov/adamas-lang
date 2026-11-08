lib LibC
  fun putchar(value : Int32) : Int32
end
struct Int32
  def piece
    42
  end
end
class BindingBox(K, V)
end
class BlockMap
  def transform(& : Int32 -> Tuple(K, V)) forall K, V
    result = BindingBox(K, V).new
    yield 7
    result
  end
end
def accept(value : BindingBox(Int32, Int32)) : Int32
  65
end
LibC.putchar(accept(BlockMap.new.transform { |item| {item.piece, item} }))
LibC.putchar(10)
