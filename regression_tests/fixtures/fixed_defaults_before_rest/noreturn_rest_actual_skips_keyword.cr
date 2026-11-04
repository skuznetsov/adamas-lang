# Expected stdout: AB. The terminal second rest actual must prevent C, D, and E.
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

def f(*items, suffix : Int32 = 65) : Nil
  LibC.putchar(68)
end

f(emit(65), terminate(), suffix: emit(67))
LibC.putchar(69)
