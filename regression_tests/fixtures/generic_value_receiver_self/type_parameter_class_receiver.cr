lib LibC
  fun putchar(value : Int32) : Int32
end

abstract struct Int
  def self.dispatch : Int32
    65
  end
end

class TypeParameterClassReceiver(T)
  def self.run : Int32
    T.dispatch
  end
end

LibC.putchar(TypeParameterClassReceiver(Int32).run)
LibC.putchar(10)
