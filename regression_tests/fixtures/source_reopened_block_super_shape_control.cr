lib LibC
  fun putchar(value : Int32) : Int32
end

module ShapeBase
  def mark(& : Int32 -> Int32) : Int32
    yield 65
  end
end

module ShapeBase
  def mark(value : Int32) : Int32
    value
  end
end

module ShapeRunner
  def mark(& : Int32 -> Int32) : Int32
    super { |value| yield value }
  end
end

class ShapeHost
  include ShapeBase
  include ShapeRunner
end

LibC.putchar(ShapeHost.new.mark { |value| value })
LibC.putchar(10)
