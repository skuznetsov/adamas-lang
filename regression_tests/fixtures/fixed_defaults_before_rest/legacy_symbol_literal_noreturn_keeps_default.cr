lib LibC
  fun putchar(code : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end

def mark_default : Int32
  LibC.putchar(66)
  90
end

def consume(value, mode : Symbol, suffix : Int32 = mark_default()) : Int32
  LibC.putchar(65)
  0
end
consume(NoReturn, mode: :fast)
