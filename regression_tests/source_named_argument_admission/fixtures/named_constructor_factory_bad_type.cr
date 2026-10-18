@[Link("c")]
lib LibC
  fun putchar(value : Int32) : Int32
end
class NamedFactoryCoexist(T)
  @value : T
  def initialize(@value : T, *, ready : Bool)
  end
  def self.new(text : String, *, ready : Bool)
    new(66, ready: ready)
  end
  def value : T
    @value
  end
end
NamedFactoryCoexist(Int32).new(true, ready: true)
