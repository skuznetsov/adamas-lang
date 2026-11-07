lib Native
 fun putchar(value : Int32) : Int32
end
macro check
 {% actual = {data: {value: "x"}, items: [1, 2], present: nil}.double_splat.stringify %}
 {% unless actual == "data: {value: \"x\"}, items: [1, 2], present: nil" %}
  {% raise "double_splat result differs" %}
 {% end %}
 Native.putchar(65)
end
check
Native.putchar(10)
