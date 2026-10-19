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

require "./arena_left"
require "./arena_right"
LibC.putchar(124)
LibC.putchar(ArenaLeft::Nested::VALUE)
LibC.putchar(ArenaRight::Nested::VALUE)
LibC.putchar(10)
