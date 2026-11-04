lib LibC
  fun putchar(value : Int32) : Int32
end

def next_value(seed : Int32) : Int32
  LibC.putchar(82)
  seed &+ 1
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

def capture(seed : Int32 = 65, marker : Int32 = next_value(seed), *items) : Int32
  LibC.putchar(seed)
  LibC.putchar(marker)
  emit_rest(*items)
  0
end

capture
capture(68)
capture(69, 70, 71, 72)
LibC.putchar(10)
