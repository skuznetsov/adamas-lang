lib C
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end

def stop : NoReturn
  C.putchar(82)
  C.exit(0)
end

def checked_result(value : Nil, flag : Bool) : Int32
  value || (if flag
    stop
  else
    70
  end)
end

C.putchar(checked_result(nil, false))
C.putchar(10)
