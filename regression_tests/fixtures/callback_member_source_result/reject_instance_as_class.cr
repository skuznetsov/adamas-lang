lib LibC
  fun putchar(value : Int32) : Int32
end
class Payload
end
class Item
  def piece
    Payload.new
  end
end
class Box(K)
end
class BlockMap
  def transform(token : K, & : Item -> Tuple(K, Bool)) forall K
    result = Box(K).new
    yield Item.new
    result
  end
end
BlockMap.new.transform(Payload) { |item| {item.piece, true} }
