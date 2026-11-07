lib Native
 fun putchar(value : Int32) : Int32
end
macro check
 {% actual = ({} of Nil => Nil).double_splat.stringify %}
 {% unless actual == "" %}
  {% raise "double_splat result differs" %}
 {% end %}
 Native.putchar(65)
end
check
Native.putchar(10)
