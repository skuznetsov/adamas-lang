lib Native
  fun putchar(value : Int32) : Int32
end
def flag; 70; end
def target; 84; end
macro project(expr)
 {% for named in expr.named_args %}
 Native.putchar({{named.name}})
 Native.putchar({{named.value}})
 {% end %}
end
project(Target.consume(flag: 65, target: 66))
