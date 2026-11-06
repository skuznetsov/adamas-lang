lib LibC
  fun putchar(value : Int32) : Int32
end
def marker
  LibC.putchar(65)
  0
end
macro invalid(pattern)
  {{ pattern.expressions(1) }}
end
invalid "a#{marker}b"
