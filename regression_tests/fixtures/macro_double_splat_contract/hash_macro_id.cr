lib Native
 fun putchar(value : Int32) : Int32
end
macro check
 {% actual = {:file => 66}.double_splat.class_name %}
 {% unless actual == "MacroId" %}
  {% raise "double_splat result differs" %}
 {% end %}
 Native.putchar(65)
end
check
Native.putchar(10)
