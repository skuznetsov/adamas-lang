lib LibC
  fun putchar(value : Int32) : Int32
end

def emit_rest
  LibC.putchar(48)
end

def emit_rest(first : Int32)
  LibC.putchar(49)
  LibC.putchar(first)
end

def emit_rest(first : Int32, second : Int32)
  LibC.putchar(50)
  LibC.putchar(first)
  LibC.putchar(second)
end

def emit(prefix : Int32 = 65, *items) : Int32
  LibC.putchar(prefix)
  emit_rest(*items)
  0
end

emit
emit(66)
emit(67, 68, 69)
LibC.putchar(10)
