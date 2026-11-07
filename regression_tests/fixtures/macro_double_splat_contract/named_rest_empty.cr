lib Native
 fun putchar(value : Int32) : Int32
end
macro check(**options)
 {% unless options.double_splat.stringify == "" %}
  {% raise "empty double_splat differs" %}
 {% end %}
 Native.putchar(65)
end
check
Native.putchar(10)
