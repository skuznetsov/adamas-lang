lib LibC
  fun putchar(c : Int32) : Int32
end

module Factory
  OFFSET = 1

  class Parent
    def initialize(@value : Int32)
    end

    def code
      @value
    end

    def self.seed(value : Int32) : self
      new(value &+ OFFSET)
    end

    def self.make(value : Int32) : self
      seed(value)
    end
  end
end

class Child < Factory::Parent
  OFFSET = 10

  def child_code
    code &+ 1
  end
end

class Other < Factory::Parent
  def self.seed(value : Int32) : self
    new(value &+ 2)
  end
end

LibC.putchar(Factory::Parent.make(64).code)
LibC.putchar(Child.make(64).child_code)
LibC.putchar(Other.make(65).code)
LibC.putchar(Child.make(66).child_code)
