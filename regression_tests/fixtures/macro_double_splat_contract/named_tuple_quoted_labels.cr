lib Native
 fun putchar(value : Int32) : Int32
end
macro check
 {% actual = {"odd key": 66, "quote\"key": "v\\x"}.double_splat.stringify %}
 {% unless actual == "\"odd key\": 66, \"quote\\\"key\": \"v\\\\x\"" %}
  {% raise "double_splat result differs" %}
 {% end %}
 Native.putchar(65)
end
check
Native.putchar(10)
