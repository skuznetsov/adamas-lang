lib Native
  fun putchar(value : Int32) : Int32
end

class Parent
  def self.new(value : Int32) : Int32
    Native.putchar(value)
  end
end

class Child < Parent
end

Child.new(66)
Native.putchar(10)
