lib LibC
  fun putchar(value : Int32) : Int32
end
def raise(value : Int32) : Int32
  value
end
def consume(value : Int32) : Int32
  value
end
LibC.putchar(consume(nil || raise(65)))
LibC.putchar(10)
