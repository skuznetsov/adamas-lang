lib LibC
  fun putchar(code : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end

def mark(code : Int32) : Int32
  LibC.putchar(code)
  code
end

def consume(mode : Int32, **options) : Int32
  LibC.putchar(67)
  0
end
consume(extra: mark(65), mode: mark(66))
