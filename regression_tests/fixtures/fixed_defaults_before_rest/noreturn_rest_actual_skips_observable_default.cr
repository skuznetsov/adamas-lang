# Expected stdout: AB. The terminal rest actual must prevent default marker C, body D, and E.
lib LibC
  fun putchar(c : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end

def emit(code : Int32) : Int32
  LibC.putchar(code)
  code
end

def terminate : NoReturn
  LibC.putchar(66)
  LibC.exit(0)
end

def observable_default : Int32
  LibC.putchar(67)
  65_i32
end

def f(*items, suffix : Int32 = observable_default) : Nil
  LibC.putchar(68)
end

f(emit(65), terminate())
LibC.putchar(69)
