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

module OuterOnce
  module Inner
    VALUE = InitEffects.mark(65) { }
  end
end
LibC.putchar(124)
LibC.putchar(OuterOnce::Inner::VALUE)
LibC.putchar(10)
