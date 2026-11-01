lib LibC
  fun putchar(value : Int32) : Int32
end

module Base
  def mark(& : Int32 -> Int32) : Int32
    yield 65
  end
end

module Base
  def mark(& : Int32 -> Int32) : Int32
    yield 66
  end
end

module Runner
  def mark(& : Int32 -> Int32) : Int32
    super { |value| yield value }
  end
end

class Host
  include Base
  include Runner
end

LibC.putchar(Host.new.mark { |value| value })
LibC.putchar(10)
