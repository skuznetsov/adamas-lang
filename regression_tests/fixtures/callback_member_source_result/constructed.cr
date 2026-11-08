lib LibC
  fun putchar(value : Int32) : Int32
end
class Piece
end
class Item
  def piece
    Piece.new
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
def accept(value : BindingBox(Piece, Item)) : Int32
  65
end
LibC.putchar(accept(BlockMap.new.transform { |item| {item.piece, item} }))
LibC.putchar(10)
