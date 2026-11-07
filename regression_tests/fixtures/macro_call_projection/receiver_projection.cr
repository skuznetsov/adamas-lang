lib Native
  fun putchar(value : Int32) : Int32
end
class Target
 def self.marker; 82; end
end
macro project(expr)
 Native.putchar({{expr.receiver}}.marker)
end
project(Target.consume(88))
