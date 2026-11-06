lib C
  fun putchar(value : Int32) : Int32
end
class UnionFactory
  def self.new : Int32 | UnionFactory.class
    65
  end
  def self.from_self : Int32 | UnionFactory.class
    self.new
  end
end
def consume_union(value : Int32 | UnionFactory.class) : Int32
  65
end
C.putchar(consume_union(UnionFactory.from_self))
