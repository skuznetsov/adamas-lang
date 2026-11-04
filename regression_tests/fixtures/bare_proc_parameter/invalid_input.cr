lib LibC
  fun exit(status : Int32) : NoReturn
end

def apply(value, transform : Proc)
  transform.call(value)
end

apply(2147483649_i64, ->(input : Int32) { input })
LibC.exit(0)
