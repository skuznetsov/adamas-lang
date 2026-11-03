lib LibC
  fun putchar(value : Int32) : Int32
end

abstract struct Int
  def dispatch(&block : self -> Int32) : Int32
    yield self
  end
end

class CallbackOwner(N)
  def self.run(& : Int32 -> Int32) : Int32
    N.dispatch do |i|
      yield i
    end
  end
end

LibC.putchar(CallbackOwner(65_i64).run { |i| i })
LibC.putchar(10)
