lib LibC
  fun putchar(value : Int32) : Int32
end
def raise(value : Int32, *, pos : Bool = true) : Int32
  pos ? value : value &+ 1
end
value = raise 64, pos: false
LibC.putchar(value)
LibC.putchar(10)
