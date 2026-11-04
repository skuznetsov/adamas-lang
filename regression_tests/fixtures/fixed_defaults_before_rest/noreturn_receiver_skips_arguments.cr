# Expected stdout: R. A terminal receiver must prevent actual markers A/B, body D, and E.
lib LibC
  fun putchar(c : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end

class Receiver
  def f(*items, suffix : Int32 = 65) : Nil
    LibC.putchar(68)
  end
end

def emit(code : Int32) : Int32
  LibC.putchar(code)
  code
end

def terminal_receiver : NoReturn
  LibC.putchar(82)
  LibC.exit(0)
end

terminal_receiver().f(emit(65), suffix: emit(66))
LibC.putchar(69)
