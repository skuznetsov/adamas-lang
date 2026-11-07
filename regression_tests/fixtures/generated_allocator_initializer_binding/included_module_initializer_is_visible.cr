lib Native
  fun putchar(value : Int32) : Int32
end

module InitializerSource
  def initialize(@value : Int32)
  end

  def value : Int32
    @value
  end
end

class Parent
  include InitializerSource
end

class Child < Parent
end

Native.putchar(Child.new(65).value)
Native.putchar(10)
