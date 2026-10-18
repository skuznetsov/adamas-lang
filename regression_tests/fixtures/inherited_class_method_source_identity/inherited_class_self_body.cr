lib LibC
  fun putchar(c : Int32) : Int32
end

module ClassBodyFactoryScope
  OFFSET = 2

  class Base
    def self.build(value : Int32) : self
      new(value &+ OFFSET)
    end
  end
end

module ClassBodyAlphaScope
  OFFSET = 8

  class Child < ClassBodyFactoryScope::Base
    def initialize(@value : Int32)
    end

    def code : Int32
      @value &+ 10
    end
  end
end

module ClassBodyBetaScope
  OFFSET = 9

  class Child < ClassBodyFactoryScope::Base
    def initialize(@value : Int32)
    end

    def code : Int32
      @value &+ 20
    end
  end
end

LibC.putchar(ClassBodyAlphaScope::Child.build(1).code &+ 52)
LibC.putchar(ClassBodyBetaScope::Child.build(2).code &+ 52)
LibC.putchar(ClassBodyBetaScope::Child.build(3).code &+ 52)
LibC.putchar(ClassBodyAlphaScope::Child.build(2).code &+ 52)
LibC.putchar(10)
