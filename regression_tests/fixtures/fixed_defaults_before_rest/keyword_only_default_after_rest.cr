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

def emit(prefix : Int32 = 65, *items, suffix : Int32 = 90) : Int32
  LibC.putchar(prefix)
  emit_rest(*items)
  LibC.putchar(suffix)
  0
end

emit
emit(66, 67, 68, suffix: 69)
emit(70, 71)
LibC.putchar(10)
