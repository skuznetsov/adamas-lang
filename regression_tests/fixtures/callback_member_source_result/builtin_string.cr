lib LibC
  fun putchar(value : Int32) : Int32
end
class String
  def piece
    42
  end
end
class BindingBox(K, V)
end
class BlockMap
  def transform(& : String -> Tuple(K, V)) forall K, V
    result = BindingBox(K, V).new
    yield "x"
    result
  end
end
def accept(value : BindingBox(Int32, String)) : Int32
  65
end
LibC.putchar(accept(BlockMap.new.transform { |item| {item.piece, item} }))
LibC.putchar(10)
