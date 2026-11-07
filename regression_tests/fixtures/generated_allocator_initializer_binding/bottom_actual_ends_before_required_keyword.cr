lib Native
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end

class Parent
  def initialize(value : Int32)
  end
end

class Child < Parent
  def initialize(value : Int32, *, file : Int32)
  end
end

Child.new(Native.exit(0))
Native.putchar(65)
Native.putchar(10)
