lib Native
  fun putchar(value : Int32) : Int32
end
module Pkg
  class Tag
  end
end
class Box(T)
  VALUE = 65
end
class Reader(T)
  def self.run
    T::VALUE
  end
end
Native.putchar(Reader(Box(Pkg::Tag)).run)
Native.putchar(10)
