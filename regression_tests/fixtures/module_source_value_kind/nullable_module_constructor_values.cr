lib C
  fun putchar(value : Int32) : Int32
end

module Marker
  abstract def code : Int32
end

class One
  include Marker
  def code : Int32
    65
  end
end

class Two
  include Marker
  def code : Int32
    66
  end
end

class Holder
  def initialize(@value : Marker?)
  end
  def code : Int32
    if item = @value
      item.code
    else
      67
    end
  end
end

C.putchar(Holder.new(One.new).code)
C.putchar(Holder.new(Two.new).code)
C.putchar(Holder.new(nil).code)
C.putchar(10)
