lib C
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end

def stop : NoReturn
  C.putchar(82)
  C.exit(0)
end

def checked_result(value : Nil) : Int32
  value || stop
end

checked_result(nil)
