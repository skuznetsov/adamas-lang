lib LibC
  fun putchar(c : Int32) : Int32
end

module InitEffects
  def self.mark(code : Int32)
    yield
    LibC.putchar(code)
    code
  end
end

module FirstOwner
  module Nested
    VALUE = InitEffects.mark(65) { }
  end
end
module SecondOwner
  module Nested
    VALUE = InitEffects.mark(66) { }
  end
end
LibC.putchar(124)
LibC.putchar(FirstOwner::Nested::VALUE)
LibC.putchar(SecondOwner::Nested::VALUE)
LibC.putchar(10)
