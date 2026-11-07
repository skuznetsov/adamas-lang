lib Native
 fun putchar(value : Int32) : Int32
end
macro check
 {% actual = {:file => 66, "other" => "kept"}.double_splat(", ").stringify %}
 {% unless actual == ":file => 66, \"other\" => \"kept\", " %}
  {% raise "double_splat result differs" %}
 {% end %}
 Native.putchar(65)
end
check
Native.putchar(10)
