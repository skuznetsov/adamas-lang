lib Native
  fun putchar(value : Int32) : Int32
end

class Parent
  def initialize(@value : Int32)
  end

  def value : Int32
    @value
  end
end

class Child < Parent
end

Native.putchar(Child.new(65).value)
Native.putchar(10)
