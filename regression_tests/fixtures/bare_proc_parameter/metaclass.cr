lib LibC
  fun exit(status : Int32) : NoReturn
end

def apply(value, transform : Proc)
  transform.call(value)
end

result = apply(Int32, ->(input : Int32.class) { 31 })
LibC.exit(1) unless result == 31
LibC.exit(0)
