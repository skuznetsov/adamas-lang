lib Native
  fun putchar(value : Int32) : Int32
end
macro project(expr)
  {{expr.name(1)}}
end
project(Target.consume(65))
