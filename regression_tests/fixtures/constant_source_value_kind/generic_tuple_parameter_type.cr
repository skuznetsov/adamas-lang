lib Native
  fun putchar(value : Int32) : Int32
end

module Pkg
  struct Tag
  end
end

def accept(value : Tuple(Pkg::Tag, Int32, Int32).class) : Int32
  65
end

class Holder(T)
  def self.marker : Int32
    accept(T)
  end
end

Native.putchar(Holder(Tuple(::Pkg::Tag, ::Int32, ::Int32)).marker)
Native.putchar(10)
