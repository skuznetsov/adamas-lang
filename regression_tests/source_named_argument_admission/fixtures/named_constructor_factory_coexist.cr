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
LibC.putchar(NamedFactoryCoexist(Int32).new(65, ready: true).value)
LibC.putchar(NamedFactoryCoexist(Int32).new("factory", ready: true).value)
LibC.putchar(10)
