lib Native
  fun putchar(value : Int32) : Int32
end

module Pkg
  class Tag
  end
end

def accept(value : Pkg::Tag.class) : Int32
  65
end

class Holder(T)
  def self.marker : Int32
    accept(T)
  end
end

Native.putchar(Holder(::Pkg::Tag).marker)
Native.putchar(10)
