lib LibC
  fun putchar(c : Int32) : Int32
end

module ParentMethodScope
  OFFSET = 65

  class Base
    def self.choose(parent value : Int32) : Int32
      OFFSET
    end
  end
end

module ChildMethodScope
  OFFSET = 66

  class Child < ParentMethodScope::Base
    def self.choose(child value : Int32) : Int32
      OFFSET
    end
  end
end

LibC.putchar(ChildMethodScope::Child.choose(parent: 1))
LibC.putchar(ChildMethodScope::Child.choose(child: 1))
LibC.putchar(10)
