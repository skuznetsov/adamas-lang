lib LibC
  fun putchar(value : Int32) : Int32
end
def raise(value : Int32, *, pos : Bool = true) : Int32
  value
end
value = raise 65, pos: 66
LibC.putchar(value)
