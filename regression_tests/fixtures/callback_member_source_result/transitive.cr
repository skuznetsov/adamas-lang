lib LibC
  fun putchar(value : Int32) : Int32
end
class Item
  def leaf
    42
  end
  def piece
    leaf
  end
end
class BindingBox(K, V)
end
class BlockMap
  def transform(& : Item -> Tuple(K, V)) forall K, V
    result = BindingBox(K, V).new
    yield Item.new
    result
  end
end
def accept(value : BindingBox(Int32, Item)) : Int32
  65
end
LibC.putchar(accept(BlockMap.new.transform { |item| {item.piece, item} }))
LibC.putchar(10)
