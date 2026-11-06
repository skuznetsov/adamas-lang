lib C
  fun putchar(value : Int32) : Int32
end
class ClassFactory
  def self.new : ClassFactory.class
    ClassFactory
  end
end
def consume_factory(value : ClassFactory.class) : Int32
  65
end
def consume_factory(value : Int32) : Int32
  66
end
C.putchar(consume_factory(ClassFactory.new))
