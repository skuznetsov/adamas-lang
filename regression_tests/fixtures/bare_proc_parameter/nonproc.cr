lib LibC
  fun exit(status : Int32) : NoReturn
end

def apply(value, transform : Proc)
  transform.call(value)
end

apply(7, true)
LibC.exit(0)
