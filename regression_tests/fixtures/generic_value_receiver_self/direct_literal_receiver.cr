lib LibC
  fun putchar(value : Int32) : Int32
end

abstract struct Int
  def dispatch(&block : self -> Int32) : Int32
    yield self
  end
end

LibC.putchar(65.dispatch { |i| i })
LibC.putchar(10)
