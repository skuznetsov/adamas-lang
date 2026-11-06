lib C
  fun putchar(value : Int32) : Int32
end
class ClassFactory
  def self.new : ClassFactory.class
    ClassFactory
  end
  def self.from_self : ClassFactory.class
    self.new
  end
end
def consume_factory(value : ClassFactory.class) : Int32
  65
end
C.putchar(consume_factory(ClassFactory.from_self))
