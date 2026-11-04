lib LibC
  fun putchar(code : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end

def terminal : NoReturn
  LibC.putchar(65)
  LibC.exit(0)
end

def f(*items, required : Int32) : Int32
  0
end
f(terminal())
