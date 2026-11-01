lib LibC
  fun putchar(value : Int32) : Int32
end

struct Box(T)
  def self.value : Int32
    68
  end
end

LibC.putchar(Box(Proc(Int32.class, Int32)).value)
LibC.putchar(10)
