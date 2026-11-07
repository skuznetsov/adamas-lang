lib Native
  fun putchar(value : Int32) : Int32
end

class Parent
  def self.new(value : Int32) : Int32
    Native.putchar(value)
  end
end

class Child < Parent
  def self.new : Int32
    Native.putchar(65)
  end
end

Child.new(66)
