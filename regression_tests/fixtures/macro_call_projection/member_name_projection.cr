lib Native
  fun putchar(value : Int32) : Int32
end
def consume; 65; end
macro project(expr)
 Native.putchar({{expr.name}})
end
project(Target.consume)
